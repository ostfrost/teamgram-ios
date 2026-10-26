import AccountContext
import Accelerate
import AnimatedStickerNode
import AvatarIntegration
import FFMpegBinding
import Foundation
import PeerInfoScreen
import Postbox
import SwiftSignalKit
import TelegramCore
import TopMessageReactions
import UIKit

public enum AvatarPeerInfoIntegration {
    private static var isAvatarFlowPresented = false

    public static func install() {
        AvatarStickerVideoPreviewDecoding.install { url, pixelSize in
            AvatarTelegramStickerVideoPreviewDecoder.decode(
                url: url,
                pixelSize: pixelSize
            )
        }

        AdditionalMessageTagReactions.files = { context in
            AvatarTelegramReactionAssigner.messageTagReactionFiles(
                context: context
            )
        }

        // Avatar data lives outside Postbox, so it is not removed with the account.
        PeerInfoAvatarModuleIntegration.accountDidLogOut = {
            Task { @MainActor in
                do {
                    try await AvatarIntegrationEntryPoint.purgeAllLocalData(reason: .logout)
                } catch {
                    NSLog("AvatarIntegration logout purge failed: %@", String(describing: error))
                }
            }
        }

        Task { @MainActor in
            AvatarIntegrationEntryPoint.configureCrashlyticsIfAvailable()
            AvatarIntegrationEntryPoint.triggerCrashlyticsNativeTestCrashIfRequested()
        }

        PeerInfoAvatarModuleIntegration.presenter = {
            presentingViewController,
            context,
            localeIdentifier,
            avatarCompletion in
            Task { @MainActor in
                self.presentAvatarFlow(
                    from: presentingViewController,
                    context: context,
                    localeIdentifier: localeIdentifier,
                    avatarCompletion: avatarCompletion
                )
            }
        }
    }

    @MainActor
    private static func presentAvatarFlow(
        from presentingViewController: UIViewController,
        context: AccountContext,
        localeIdentifier: String,
        avatarCompletion: @escaping (UIImage?) -> Void
    ) {
        guard self.isAvatarFlowPresented == false else {
            return
        }
        self.isAvatarFlowPresented = true
        let stickerPackAssigner = AvatarTelegramStickerPackAssigner(
            context: context
        )
        let reactionAssigner = AvatarTelegramReactionAssigner(
            context: context
        )
        AvatarIntegrationEntryPoint.presentAvatarFlow(
            from: self.topMostViewController(from: presentingViewController),
            localeIdentifier: localeIdentifier,
            onClose: {
                self.isAvatarFlowPresented = false
            },
            onStickerPackReady: {
                [stickerPackAssigner] assignment,
                completion in
                stickerPackAssigner.assign(
                    assignment,
                    completion: completion
                )
            },
            onReactionsReady: {
                [reactionAssigner] assignment,
                completion in
                reactionAssigner.assign(
                    assignment,
                    completion: completion
                )
            },
            onAvatarCreated: { result in
                self.isAvatarFlowPresented = false
                avatarCompletion(result.image)
            }
        )
    }

    @MainActor
    private static func topMostViewController(
        from viewController: UIViewController
    ) -> UIViewController {
        if let presented = viewController.presentedViewController {
            return self.topMostViewController(from: presented)
        }
        if let navigationController = viewController as? UINavigationController,
           let visibleViewController = navigationController.visibleViewController {
            return self.topMostViewController(from: visibleViewController)
        }
        if let tabBarController = viewController as? UITabBarController,
           let selectedViewController = tabBarController.selectedViewController {
            return self.topMostViewController(from: selectedViewController)
        }
        return viewController
    }
}

final class AvatarTelegramReactionAssigner {
    private static let telegramCustomEmojiSize: Int32 = 100
    private static let telegramMaximumVideoBytes = 256 * 1024
    private static let telegramMaximumVideoDuration = 3.0
    private static let transcodingQueue = Queue(
        name: "AvatarIntegration.TelegramReaction.Transcoding",
        qos: .utility
    )

    private struct PendingAssignment {
        let assignment: AvatarReactionAssignment
        var completions: [AvatarReactionAssignmentCompletion]
    }

    private struct PreparedReaction {
        let emoji: String
        let sticker: ImportSticker
    }

    private enum ReconciliationOperation {
        case add(ImportSticker)
        case replace(StickerPackItem, ImportSticker)
    }

    private let context: AccountContext
    private let disposable = MetaDisposable()
    private var pendingAssignments: [PendingAssignment] = []
    private var isAssigning = false

    init(context: AccountContext) {
        self.context = context
    }

    deinit {
        self.disposable.dispose()
    }

    static func messageTagReactionFiles(
        context: AccountContext
    ) -> Signal<[TelegramMediaFile.Accessor], NoError> {
        let shortName = self.reactionSetShortName(context: context)
        return context.engine.stickers.getMyStickerSets()
        |> take(1)
        |> mapToSignal { sets -> Signal<[TelegramMediaFile.Accessor], NoError> in
            guard let info = sets.first(where: {
                $0.0.shortName.caseInsensitiveCompare(shortName) == .orderedSame
            })?.0 else {
                NSLog(
                    "Avatar Telegram reactions: message tag source unavailable set=%@",
                    shortName
                )
                return .single([])
            }
            let reference = StickerPackReference.id(
                id: info.id.id,
                accessHash: info.accessHash
            )
            return context.engine.stickers.loadedStickerPack(
                reference: reference,
                forceActualized: false,
                ignoreCache: false
            )
            |> map { loadedPack -> [TelegramMediaFile.Accessor]? in
                switch loadedPack {
                case let .result(_, items, _):
                    let expectedEmojis = ["😂", "😍", "😉"]
                    var filesByEmoji: [String: TelegramMediaFile.Accessor] = [:]
                    for item in items {
                        guard let emoji = self.stickerEmoji(item.file._parse()),
                              expectedEmojis.contains(emoji),
                              filesByEmoji[emoji] == nil else {
                            continue
                        }
                        filesByEmoji[emoji] = item.file
                    }
                    let files = expectedEmojis.compactMap { filesByEmoji[$0] }
                    NSLog(
                        "Avatar Telegram reactions: message tag source resolved set=%@ units=%d",
                        shortName,
                        files.count
                    )
                    return files
                case .none:
                    return []
                case .fetching:
                    return nil
                }
            }
            |> filter { $0 != nil }
            |> map { $0 ?? [] }
            |> take(1)
        }
    }

    @MainActor
    func assign(
        _ assignment: AvatarReactionAssignment,
        completion: @escaping AvatarReactionAssignmentCompletion
    ) {
        if let existingIndex = self.pendingAssignments.firstIndex(where: {
            $0.assignment.avatarID == assignment.avatarID
                && $0.assignment.paramsHash == assignment.paramsHash
        }) {
            self.pendingAssignments[existingIndex].completions.append(completion)
            return
        }
        self.pendingAssignments.append(PendingAssignment(
            assignment: assignment,
            completions: [completion]
        ))
        NSLog(
            "Avatar Telegram reactions: assignment queued avatar=%lld hash=%@",
            assignment.avatarID,
            assignment.paramsHash
        )
        self.startNextIfPossible()
    }

    @MainActor
    private func startNextIfPossible() {
        guard !self.isAssigning,
              let pending = self.pendingAssignments.first else {
            return
        }
        self.isAssigning = true
        let shortName = self.reactionSetShortName()
        self.disposable.set((
            self.context.engine.stickers.getMyStickerSets()
            |> take(1)
            |> deliverOnMainQueue
        ).start(next: { [weak self] sets in
            guard let self else {
                return
            }
            if let existing = sets.first(where: {
                $0.0.shortName.caseInsensitiveCompare(shortName) == .orderedSame
            })?.0 {
                let importedParamsHash = self.importedParamsHash(
                    shortName: shortName
                )
                if importedParamsHash == pending.assignment.paramsHash {
                    NSLog(
                        "Avatar Telegram reactions: update skipped, hash already imported avatar=%lld hash=%@",
                        pending.assignment.avatarID,
                        pending.assignment.paramsHash
                    )
                    self.completeCurrent(.success(()))
                    return
                }
                NSLog(
                    "Avatar Telegram reactions: updating existing set avatar=%lld previousHash=%@ newHash=%@",
                    pending.assignment.avatarID,
                    importedParamsHash ?? "<none>",
                    pending.assignment.paramsHash
                )
                self.updateExistingSet(
                    info: existing,
                    pending: pending,
                    shortName: shortName
                )
            } else {
                self.createSet(
                    pending: pending,
                    shortName: shortName
                )
            }
        }))
    }

    @MainActor
    private func createSet(
        pending: PendingAssignment,
        shortName: String
    ) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                let preparedReactions = try await self.makeImportStickers(
                    assignment: pending.assignment
                )
                self.createSet(
                    pending: pending,
                    shortName: shortName,
                    preparedReactions: preparedReactions
                )
            } catch {
                self.completeCurrent(.failure(error))
            }
        }
    }

    @MainActor
    private func createSet(
        pending: PendingAssignment,
        shortName: String,
        preparedReactions: [PreparedReaction]
    ) {
        NSLog(
            "Avatar Telegram reactions: creating set avatar=%lld units=%d telegramDimensions=%dx%d",
            pending.assignment.avatarID,
            preparedReactions.count,
            Self.telegramCustomEmojiSize,
            Self.telegramCustomEmojiSize
        )

        var didComplete = false
        self.disposable.set((
            self.context.engine.stickers.createStickerSet(
                title: "My Avatar Reactions",
                shortName: shortName,
                stickers: preparedReactions.map(\.sticker),
                thumbnail: nil,
                type: .emoji(content: .video, textColored: false),
                software: "AvatarIntegration-iOS"
            )
            |> deliverOnMainQueue
        ).start(next: { [weak self] status in
            guard let self, !didComplete else {
                return
            }
            guard case let .complete(info, items) = status else {
                return
            }
            didComplete = true
            self.disposable.set((
                self.context.engine.stickers.addStickerPackInteractively(
                    info: info,
                    items: items
                )
                |> deliverOnMainQueue
            ).start(completed: { [weak self] in
                guard let self else {
                    return
                }
                self.storeImportedParamsHash(
                    pending.assignment.paramsHash,
                    shortName: shortName
                )
                NSLog(
                    "Avatar Telegram reactions: set created avatar=%lld hash=%@ units=%d",
                    pending.assignment.avatarID,
                    pending.assignment.paramsHash,
                    pending.assignment.units.count
                )
                self.completeCurrent(.success(()))
            }))
        }, error: { [weak self] _ in
            self?.completeCurrent(.failure(Self.error(
                code: 2,
                description: "Telegram reaction set creation failed"
            )))
        }))
    }

    @MainActor
    private func updateExistingSet(
        info: StickerPackCollectionInfo,
        pending: PendingAssignment,
        shortName: String
    ) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                let preparedReactions = try await self.makeImportStickers(
                    assignment: pending.assignment
                )
                self.updateExistingSet(
                    info: info,
                    pending: pending,
                    shortName: shortName,
                    preparedReactions: preparedReactions
                )
            } catch {
                self.completeCurrent(.failure(error))
            }
        }
    }

    @MainActor
    private func updateExistingSet(
        info: StickerPackCollectionInfo,
        pending: PendingAssignment,
        shortName: String,
        preparedReactions: [PreparedReaction]
    ) {
        let reference = StickerPackReference.id(
            id: info.id.id,
            accessHash: info.accessHash
        )
        self.disposable.set((
            self.context.engine.stickers.loadedStickerPack(
                reference: reference,
                forceActualized: true,
                ignoreCache: true
            )
            |> deliverOnMainQueue
        ).start(next: { [weak self] loadedPack in
            guard let self else {
                return
            }
            switch loadedPack {
            case let .result(_, items, _):
                let operations = self.reconciliationOperations(
                    currentItems: items,
                    newReactions: preparedReactions
                )
                NSLog(
                    "Avatar Telegram reactions: reconciliation started avatar=%lld currentUnits=%d operations=%d",
                    pending.assignment.avatarID,
                    items.count,
                    operations.count
                )
                self.perform(
                    operations: operations,
                    index: 0,
                    reference: reference,
                    pending: pending,
                    shortName: shortName
                )
            case .none:
                self.completeCurrent(.failure(Self.error(
                    code: 3,
                    description: "Telegram reaction set is unavailable"
                )))
            case .fetching:
                break
            }
        }))
    }

    @MainActor
    private func perform(
        operations: [ReconciliationOperation],
        index: Int,
        reference: StickerPackReference,
        pending: PendingAssignment,
        shortName: String
    ) {
        guard index < operations.count else {
            self.finishUpdate(
                reference: reference,
                pending: pending,
                shortName: shortName
            )
            return
        }

        switch operations[index] {
        case let .replace(previousItem, sticker):
            self.disposable.set((
                self.context.engine.stickers.replaceSticker(
                    previousSticker: .stickerPack(
                        stickerPack: reference,
                        media: previousItem.file._parse()
                    ),
                    sticker: sticker
                )
                |> deliverOnMainQueue
            ).start(error: { [weak self] _ in
                self?.completeCurrent(.failure(Self.error(
                    code: 4,
                    description: "Telegram reaction replacement failed"
                )))
            }, completed: { [weak self] in
                self?.perform(
                    operations: operations,
                    index: index + 1,
                    reference: reference,
                    pending: pending,
                    shortName: shortName
                )
            }))
        case let .add(sticker):
            var didAdvance = false
            self.disposable.set((
                self.context.engine.stickers.addStickerToStickerSet(
                    packReference: reference,
                    sticker: sticker
                )
                |> deliverOnMainQueue
            ).start(next: { [weak self] added in
                guard let self, !didAdvance else {
                    return
                }
                guard added else {
                    self.completeCurrent(.failure(Self.error(
                        code: 5,
                        description: "Telegram reaction addition failed"
                    )))
                    return
                }
                didAdvance = true
                self.perform(
                    operations: operations,
                    index: index + 1,
                    reference: reference,
                    pending: pending,
                    shortName: shortName
                )
            }, error: { [weak self] _ in
                self?.completeCurrent(.failure(Self.error(
                    code: 5,
                    description: "Telegram reaction addition failed"
                )))
            }))
        }
    }

    @MainActor
    private func finishUpdate(
        reference: StickerPackReference,
        pending: PendingAssignment,
        shortName: String
    ) {
        self.disposable.set((
            self.context.engine.stickers.loadedStickerPack(
                reference: reference,
                forceActualized: true,
                ignoreCache: true
            )
            |> deliverOnMainQueue
        ).start(next: { [weak self] loadedPack in
            guard let self else {
                return
            }
            guard case let .result(info, items, installed) = loadedPack else {
                if case .none = loadedPack {
                    self.completeCurrent(.failure(Self.error(
                        code: 6,
                        description: "Updated Telegram reaction set is unavailable"
                    )))
                }
                return
            }

            let complete: () -> Void = { [weak self] in
                guard let self else {
                    return
                }
                self.storeImportedParamsHash(
                    pending.assignment.paramsHash,
                    shortName: shortName
                )
                NSLog(
                    "Avatar Telegram reactions: set updated avatar=%lld hash=%@ units=%d",
                    pending.assignment.avatarID,
                    pending.assignment.paramsHash,
                    pending.assignment.units.count
                )
                self.completeCurrent(.success(()))
            }
            if installed {
                complete()
            } else {
                self.disposable.set((
                    self.context.engine.stickers.addStickerPackInteractively(
                        info: info._parse(),
                        items: items
                    )
                    |> deliverOnMainQueue
                ).start(completed: complete))
            }
        }))
    }

    @MainActor
    private func completeCurrent(_ result: Result<Void, Error>) {
        guard !self.pendingAssignments.isEmpty else {
            self.isAssigning = false
            return
        }
        let pending = self.pendingAssignments.removeFirst()
        self.isAssigning = false
        for completion in pending.completions {
            completion(result)
        }
        self.startNextIfPossible()
    }

    @MainActor
    private func makeImportStickers(
        assignment: AvatarReactionAssignment
    ) async throws -> [PreparedReaction] {
        let expectedEmotionIDs = Set(["laugh", "love", "wink"])
        guard assignment.units.count == expectedEmotionIDs.count,
              Set(assignment.units.map(\.emotionID)) == expectedEmotionIDs,
              Set(assignment.units.map(\.emoji)).count == expectedEmotionIDs.count else {
            throw Self.error(
                code: 1,
                description: "Avatar reaction assignment must contain laugh, love, and wink"
            )
        }
        var preparedReactions: [PreparedReaction] = []
        for unit in assignment.units {
            guard unit.width == 512,
                  unit.height == 512,
                  unit.durationSeconds > 0,
                  unit.durationSeconds <= Self.telegramMaximumVideoDuration else {
                throw Self.error(
                    code: 1,
                    description: "Avatar reaction source violates Telegram limits"
                )
            }
            let customEmojiURL = try await Self.transcodeCustomEmojiWebM(
                unit: unit
            )
            let data = try Data(contentsOf: customEmojiURL)
            guard data.count >= 4,
                  data.count <= Self.telegramMaximumVideoBytes,
                  data.prefix(4) == Data([0x1A, 0x45, 0xDF, 0xA3]) else {
                throw Self.error(
                    code: 7,
                    description: "Transcoded Telegram reaction file is invalid"
                )
            }
            let resource = LocalFileMediaResource(
                fileId: Int64.random(in: Int64.min ... Int64.max),
                size: Int64(data.count)
            )
            self.context.account.postbox.mediaBox.storeResourceData(
                resource.id,
                data: data,
                synchronous: true
            )
            preparedReactions.append(PreparedReaction(
                emoji: unit.emoji,
                sticker: ImportSticker(
                    resource: .standalone(resource: resource),
                    emojis: [unit.emoji],
                    dimensions: PixelDimensions(
                        width: Self.telegramCustomEmojiSize,
                        height: Self.telegramCustomEmojiSize
                    ),
                    duration: unit.durationSeconds,
                    mimeType: "video/webm",
                    keywords: "avatar_reaction_\(unit.emotionID)"
                )
            ))
        }
        return preparedReactions
    }

    private static func transcodeCustomEmojiWebM(
        unit: AvatarReactionAssignment.Unit
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            Self.transcodingQueue.async {
                do {
                    continuation.resume(
                        returning: try Self.transcodeCustomEmojiWebMSynchronously(
                            unit: unit
                        )
                    )
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func transcodeCustomEmojiWebMSynchronously(
        unit: AvatarReactionAssignment.Unit
    ) throws -> URL {
        let fileManager = FileManager.default
        let outputDirectory = unit.fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("CustomEmoji", isDirectory: true)
        try fileManager.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        let outputURL = outputDirectory.appendingPathComponent(
            "\(unit.emotionID)-100x100-v1.webm"
        )
        if Self.isReusableCustomEmojiFile(
            outputURL,
            sourceURL: unit.fileURL
        ) {
            return outputURL
        }

        let temporaryURL = outputDirectory.appendingPathComponent(
            ".\(unit.emotionID)-\(UUID().uuidString).webm"
        )
        defer {
            try? fileManager.removeItem(at: temporaryURL)
        }

        FFMpegGlobals.initializeGlobals()
        guard let frameSource = VideoStickerDirectFrameSource(
            queue: Self.transcodingQueue,
            path: unit.fileURL.path,
            isVP9: true,
            width: Int(Self.telegramCustomEmojiSize),
            height: Int(Self.telegramCustomEmojiSize),
            cachePathPrefix: nil,
            unpremultiplyAlpha: false
        ) else {
            throw Self.error(
                code: 7,
                description: "Telegram reaction WebM decoding failed"
            )
        }
        let frameRate = Int32(min(30, max(1, frameSource.frameRate)))
        let maximumFrameCount = Int(frameRate) * Int(
            Self.telegramMaximumVideoDuration
        )
        let writer = FFMpegVideoWriter()
        guard writer.setup(
            withOutputPath: temporaryURL.path,
            width: Self.telegramCustomEmojiSize,
            height: Self.telegramCustomEmojiSize,
            bitrate: 240 * 1000,
            framerate: frameRate
        ) else {
            throw Self.error(
                code: 7,
                description: "Telegram reaction WebM encoder setup failed"
            )
        }

        var didFinalize = false
        defer {
            if !didFinalize {
                _ = writer.finalizeVideo()
            }
        }
        var frameCount = 0
        while let frame = frameSource.takeFrame(draw: true) {
            guard frameCount < maximumFrameCount,
                  frame.width == Int(Self.telegramCustomEmojiSize),
                  frame.height == Int(Self.telegramCustomEmojiSize),
                  case .argb = frame.type else {
                throw Self.error(
                    code: 7,
                    description: "Telegram reaction decoded frame is invalid"
                )
            }
            let encodedFrame = try Self.makeFFMpegFrame(frame)
            guard writer.encode(encodedFrame) else {
                throw Self.error(
                    code: 7,
                    description: "Telegram reaction WebM frame encoding failed"
                )
            }
            frameCount += 1
        }
        guard frameCount > 0,
              writer.finalizeVideo() else {
            throw Self.error(
                code: 7,
                description: "Telegram reaction WebM finalization failed"
            )
        }
        didFinalize = true

        let data = try Data(contentsOf: temporaryURL)
        guard data.count >= 4,
              data.count <= Self.telegramMaximumVideoBytes,
              data.prefix(4) == Data([0x1A, 0x45, 0xDF, 0xA3]) else {
            throw Self.error(
                code: 7,
                description: "Telegram reaction WebM output violates Telegram limits"
            )
        }
        if fileManager.fileExists(atPath: outputURL.path) {
            _ = try fileManager.replaceItemAt(
                outputURL,
                withItemAt: temporaryURL
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: outputURL)
        }
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableOutputURL = outputURL
        try mutableOutputURL.setResourceValues(resourceValues)
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: outputURL.path
        )
        NSLog(
            "Avatar Telegram reactions: transcoded emotion=%@ source=512x512 output=100x100 frames=%d fps=%d bytes=%d",
            unit.emotionID,
            frameCount,
            frameRate,
            data.count
        )
        return outputURL
    }

    private static func makeFFMpegFrame(
        _ frame: AnimatedStickerFrame
    ) throws -> FFMpegAVFrame {
        var pixelRange = vImage_YpCbCrPixelRange(
            Yp_bias: 16,
            CbCr_bias: 128,
            YpRangeMax: 235,
            CbCrRangeMax: 240,
            YpMax: 235,
            YpMin: 16,
            CbCrMax: 240,
            CbCrMin: 16
        )
        var conversionInfo = vImage_ARGBToYpCbCr()
        guard vImageConvert_ARGBToYpCbCr_GenerateConversion(
            kvImage_ARGBToYpCbCrMatrix_ITU_R_709_2,
            &pixelRange,
            &conversionInfo,
            kvImageARGB8888,
            kvImage420Yp8_Cb8_Cr8,
            vImage_Flags(kvImageNoFlags)
        ) == kvImageNoError else {
            throw Self.error(
                code: 7,
                description: "Telegram reaction color conversion setup failed"
            )
        }

        let width = Int(Self.telegramCustomEmojiSize)
        let height = Int(Self.telegramCustomEmojiSize)
        let output = FFMpegAVFrame(
            pixelFormat: .YUVA,
            width: Self.telegramCustomEmojiSize,
            height: Self.telegramCustomEmojiSize
        )
        let conversionSucceeded = frame.data.withUnsafeBytes { buffer in
            guard let sourceBytes = buffer.baseAddress else {
                return false
            }
            var sourceBuffer = vImage_Buffer(
                data: UnsafeMutableRawPointer(mutating: sourceBytes),
                height: vImagePixelCount(height),
                width: vImagePixelCount(width),
                rowBytes: frame.bytesPerRow
            )
            var yBuffer = vImage_Buffer(
                data: output.data[0],
                height: vImagePixelCount(height),
                width: vImagePixelCount(width),
                rowBytes: Int(output.lineSize[0])
            )
            var uBuffer = vImage_Buffer(
                data: output.data[1],
                height: vImagePixelCount(height / 2),
                width: vImagePixelCount(width / 2),
                rowBytes: Int(output.lineSize[1])
            )
            var vBuffer = vImage_Buffer(
                data: output.data[2],
                height: vImagePixelCount(height / 2),
                width: vImagePixelCount(width / 2),
                rowBytes: Int(output.lineSize[2])
            )
            var alphaBuffer = vImage_Buffer(
                data: output.data[3],
                height: vImagePixelCount(height),
                width: vImagePixelCount(width),
                rowBytes: Int(output.lineSize[3])
            )
            var localConversionInfo = conversionInfo
            let colorResult = vImageConvert_ARGB8888To420Yp8_Cb8_Cr8(
                &sourceBuffer,
                &yBuffer,
                &uBuffer,
                &vBuffer,
                &localConversionInfo,
                [3, 2, 1, 0],
                vImage_Flags(kvImageDoNotTile)
            )
            let alphaResult = vImageExtractChannel_ARGB8888(
                &sourceBuffer,
                &alphaBuffer,
                3,
                vImage_Flags(kvImageDoNotTile)
            )
            return colorResult == kvImageNoError
                && alphaResult == kvImageNoError
        }
        guard conversionSucceeded else {
            throw Self.error(
                code: 7,
                description: "Telegram reaction frame conversion failed"
            )
        }
        return output
    }

    private static func isReusableCustomEmojiFile(
        _ outputURL: URL,
        sourceURL: URL
    ) -> Bool {
        guard let outputData = try? Data(contentsOf: outputURL),
              outputData.count >= 4,
              outputData.count <= Self.telegramMaximumVideoBytes,
              outputData.prefix(4) == Data([0x1A, 0x45, 0xDF, 0xA3]) else {
            return false
        }
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        let sourceDate = try? sourceURL.resourceValues(forKeys: keys)
            .contentModificationDate
        let outputDate = try? outputURL.resourceValues(forKeys: keys)
            .contentModificationDate
        guard let sourceDate, let outputDate else {
            return false
        }
        return outputDate >= sourceDate
    }

    private func reconciliationOperations(
        currentItems: [StickerPackItem],
        newReactions: [PreparedReaction]
    ) -> [ReconciliationOperation] {
        var currentItemsByEmoji: [String: StickerPackItem] = [:]
        for item in currentItems {
            guard let emoji = Self.stickerEmoji(item.file._parse()),
                  currentItemsByEmoji[emoji] == nil else {
                continue
            }
            currentItemsByEmoji[emoji] = item
        }
        return newReactions.map { preparedReaction in
            if let currentItem = currentItemsByEmoji[preparedReaction.emoji] {
                return .replace(currentItem, preparedReaction.sticker)
            } else {
                return .add(preparedReaction.sticker)
            }
        }
    }

    private func reactionSetShortName() -> String {
        Self.reactionSetShortName(context: self.context)
    }

    private static func reactionSetShortName(
        context: AccountContext
    ) -> String {
        let accountID = UInt64(bitPattern: context.account.peerId.toInt64())
        return String(format: "sends_avatar_reactions_%016llx", accountID)
    }

    private func importedParamsHash(shortName: String) -> String? {
        UserDefaults.standard.string(forKey: self.paramsHashKey(
            shortName: shortName
        ))
    }

    private func storeImportedParamsHash(
        _ paramsHash: String,
        shortName: String
    ) {
        UserDefaults.standard.set(
            paramsHash,
            forKey: self.paramsHashKey(shortName: shortName)
        )
    }

    private func paramsHashKey(shortName: String) -> String {
        "AvatarIntegration.TelegramReactionSet.\(shortName).paramsHash"
    }

    private static func stickerEmoji(_ file: TelegramMediaFile) -> String? {
        for attribute in file.attributes {
            if case let .Sticker(displayText, _, _) = attribute,
               !displayText.isEmpty {
                return displayText
            }
        }
        return nil
    }

    private static func error(
        code: Int,
        description: String
    ) -> NSError {
        NSError(
            domain: "AvatarTelegramReactionAssigner",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }
}

final class AvatarTelegramStickerPackAssigner {
    private struct PendingAssignment {
        let assignment: AvatarStickerPackAssignment
        var completions: [AvatarStickerPackAssignmentCompletion]
    }

    private struct PreparedSticker {
        let emoji: String
        let sticker: ImportSticker
    }

    private enum ReconciliationOperation {
        case add(ImportSticker)
        case replace(StickerPackItem, ImportSticker)
    }

    private let context: AccountContext
    private let disposable = MetaDisposable()
    private var pendingAssignments: [PendingAssignment] = []
    private var isAssigning = false

    init(context: AccountContext) {
        self.context = context
    }

    deinit {
        self.disposable.dispose()
    }

    @MainActor
    func assign(
        _ assignment: AvatarStickerPackAssignment,
        completion: @escaping AvatarStickerPackAssignmentCompletion
    ) {
        if let existingIndex = self.pendingAssignments.firstIndex(where: {
            $0.assignment.avatarID == assignment.avatarID
                && $0.assignment.paramsHash == assignment.paramsHash
        }) {
            self.pendingAssignments[existingIndex].completions.append(completion)
            return
        }
        self.pendingAssignments.append(PendingAssignment(
            assignment: assignment,
            completions: [completion]
        ))
        NSLog(
            "Avatar Telegram stickers: assignment queued avatar=%lld hash=%@",
            assignment.avatarID,
            assignment.paramsHash
        )
        self.startNextIfPossible()
    }

    @MainActor
    private func startNextIfPossible() {
        guard !self.isAssigning,
              let pending = self.pendingAssignments.first else {
            return
        }
        self.isAssigning = true
        let shortName = self.stickerSetShortName(
            avatarID: pending.assignment.avatarID
        )
        self.disposable.set((
            self.context.engine.stickers.getMyStickerSets()
            |> take(1)
            |> deliverOnMainQueue
        ).start(next: { [weak self] sets in
            guard let self else {
                return
            }
            if let existing = sets.first(where: {
                $0.0.shortName.caseInsensitiveCompare(shortName) == .orderedSame
            })?.0 {
                let importedParamsHash = self.importedParamsHash(
                    shortName: shortName
                )
                if importedParamsHash == pending.assignment.paramsHash {
                    NSLog(
                        "Avatar Telegram stickers: update skipped, hash already imported avatar=%lld hash=%@",
                        pending.assignment.avatarID,
                        pending.assignment.paramsHash
                    )
                    self.completeCurrent(.success(()))
                    return
                }
                NSLog(
                    "Avatar Telegram stickers: updating existing set avatar=%lld previousHash=%@ newHash=%@",
                    pending.assignment.avatarID,
                    importedParamsHash ?? "<none>",
                    pending.assignment.paramsHash
                )
                self.updateExistingSet(
                    info: existing,
                    pending: pending,
                    shortName: shortName
                )
            } else {
                self.createSet(
                    pending: pending,
                    shortName: shortName
                )
            }
        }))
    }

    @MainActor
    private func createSet(
        pending: PendingAssignment,
        shortName: String
    ) {
        let preparedStickers: [PreparedSticker]
        do {
            preparedStickers = try self.makeImportStickers(
                assignment: pending.assignment
            )
        } catch {
            self.completeCurrent(.failure(error))
            return
        }

        var didComplete = false
        self.disposable.set((
            self.context.engine.stickers.createStickerSet(
                title: Self.stickerSetTitle(
                    avatarID: pending.assignment.avatarID
                ),
                shortName: shortName,
                stickers: preparedStickers.map(\.sticker),
                thumbnail: nil,
                type: .stickers(content: .image),
                software: "AvatarIntegration-iOS"
            )
            |> deliverOnMainQueue
        ).start(next: { [weak self] status in
            guard let self, !didComplete else {
                return
            }
            guard case let .complete(info, items) = status else {
                return
            }
            didComplete = true
            self.disposable.set((
                self.context.engine.stickers.addStickerPackInteractively(
                    info: info,
                    items: items
                )
                |> deliverOnMainQueue
            ).start(completed: { [weak self] in
                guard let self else {
                    return
                }
                self.storeImportedParamsHash(
                    pending.assignment.paramsHash,
                    shortName: shortName
                )
                NSLog(
                    "Avatar Telegram stickers: set created avatar=%lld hash=%@ units=%d",
                    pending.assignment.avatarID,
                    pending.assignment.paramsHash,
                    pending.assignment.units.count
                )
                self.completeCurrent(.success(()))
            }))
        }, error: { [weak self] _ in
            self?.completeCurrent(.failure(Self.error(
                code: 2,
                description: "Telegram sticker set creation failed"
            )))
        }))
    }

    @MainActor
    private func updateExistingSet(
        info: StickerPackCollectionInfo,
        pending: PendingAssignment,
        shortName: String
    ) {
        let preparedStickers: [PreparedSticker]
        do {
            preparedStickers = try self.makeImportStickers(
                assignment: pending.assignment
            )
        } catch {
            self.completeCurrent(.failure(error))
            return
        }

        let reference = StickerPackReference.id(
            id: info.id.id,
            accessHash: info.accessHash
        )
        self.disposable.set((
            self.context.engine.stickers.loadedStickerPack(
                reference: reference,
                forceActualized: true,
                ignoreCache: true
            )
            |> deliverOnMainQueue
        ).start(next: { [weak self] loadedPack in
            guard let self else {
                return
            }
            switch loadedPack {
            case let .result(_, items, _):
                let operations = self.reconciliationOperations(
                    currentItems: items,
                    newStickers: preparedStickers
                )
                NSLog(
                    "Avatar Telegram stickers: reconciliation started avatar=%lld currentUnits=%d operations=%d",
                    pending.assignment.avatarID,
                    items.count,
                    operations.count
                )
                self.perform(
                    operations: operations,
                    index: 0,
                    reference: reference,
                    pending: pending,
                    shortName: shortName
                )
            case .none:
                self.completeCurrent(.failure(Self.error(
                    code: 3,
                    description: "Telegram sticker set is unavailable"
                )))
            case .fetching:
                break
            }
        }))
    }

    @MainActor
    private func perform(
        operations: [ReconciliationOperation],
        index: Int,
        reference: StickerPackReference,
        pending: PendingAssignment,
        shortName: String
    ) {
        guard index < operations.count else {
            self.finishUpdate(
                reference: reference,
                pending: pending,
                shortName: shortName
            )
            return
        }

        switch operations[index] {
        case let .replace(previousItem, sticker):
            self.disposable.set((
                self.context.engine.stickers.replaceSticker(
                    previousSticker: .stickerPack(
                        stickerPack: reference,
                        media: previousItem.file._parse()
                    ),
                    sticker: sticker
                )
                |> deliverOnMainQueue
            ).start(error: { [weak self] _ in
                self?.completeCurrent(.failure(Self.error(
                    code: 4,
                    description: "Telegram sticker replacement failed"
                )))
            }, completed: { [weak self] in
                self?.perform(
                    operations: operations,
                    index: index + 1,
                    reference: reference,
                    pending: pending,
                    shortName: shortName
                )
            }))
        case let .add(sticker):
            var didAdvance = false
            self.disposable.set((
                self.context.engine.stickers.addStickerToStickerSet(
                    packReference: reference,
                    sticker: sticker
                )
                |> deliverOnMainQueue
            ).start(next: { [weak self] added in
                guard let self, !didAdvance else {
                    return
                }
                guard added else {
                    self.completeCurrent(.failure(Self.error(
                        code: 5,
                        description: "Telegram sticker addition failed"
                    )))
                    return
                }
                didAdvance = true
                self.perform(
                    operations: operations,
                    index: index + 1,
                    reference: reference,
                    pending: pending,
                    shortName: shortName
                )
            }, error: { [weak self] _ in
                self?.completeCurrent(.failure(Self.error(
                    code: 5,
                    description: "Telegram sticker addition failed"
                )))
            }))
        }
    }

    @MainActor
    private func finishUpdate(
        reference: StickerPackReference,
        pending: PendingAssignment,
        shortName: String
    ) {
        self.disposable.set((
            self.context.engine.stickers.loadedStickerPack(
                reference: reference,
                forceActualized: true,
                ignoreCache: true
            )
            |> deliverOnMainQueue
        ).start(next: { [weak self] loadedPack in
            guard let self else {
                return
            }
            guard case let .result(info, items, _) = loadedPack else {
                if case .none = loadedPack {
                    self.completeCurrent(.failure(Self.error(
                        code: 6,
                        description: "Updated Telegram sticker set is unavailable"
                    )))
                }
                return
            }

            let complete: () -> Void = { [weak self] in
                guard let self else {
                    return
                }
                self.storeImportedParamsHash(
                    pending.assignment.paramsHash,
                    shortName: shortName
                )
                NSLog(
                    "Avatar Telegram stickers: set updated avatar=%lld hash=%@ units=%d",
                    pending.assignment.avatarID,
                    pending.assignment.paramsHash,
                    pending.assignment.units.count
                )
                self.completeCurrent(.success(()))
            }
            // Installs the set if needed and moves it to the top of the
            // installed packs, so the updated avatar pack is shown first.
            let moveToTop: () -> Void = { [weak self] in
                guard let self else {
                    return
                }
                self.disposable.set((
                    self.context.engine.stickers.addStickerPackInteractively(
                        info: info._parse(),
                        items: items
                    )
                    |> deliverOnMainQueue
                ).start(completed: complete))
            }
            // Sets created before the per-avatar title get renamed; a failed
            // rename does not fail the assignment.
            let expectedTitle = Self.stickerSetTitle(
                avatarID: pending.assignment.avatarID
            )
            guard info.title != expectedTitle else {
                moveToTop()
                return
            }
            self.disposable.set((
                self.context.engine.stickers.renameStickerSet(
                    packReference: reference,
                    title: expectedTitle
                )
                |> deliverOnMainQueue
            ).start(error: { _ in
                NSLog(
                    "Avatar Telegram stickers: set rename failed avatar=%lld",
                    pending.assignment.avatarID
                )
                moveToTop()
            }, completed: {
                moveToTop()
            }))
        }))
    }

    @MainActor
    private func completeCurrent(_ result: Result<Void, Error>) {
        guard !self.pendingAssignments.isEmpty else {
            self.isAssigning = false
            return
        }
        let pending = self.pendingAssignments.removeFirst()
        self.isAssigning = false
        for completion in pending.completions {
            completion(result)
        }
        self.startNextIfPossible()
    }

    @MainActor
    private func makeImportStickers(
        assignment: AvatarStickerPackAssignment
    ) throws -> [PreparedSticker] {
        let staticUnits = assignment.units.filter {
            $0.contentKind == .staticWebP
        }
        let videoUnits = assignment.units.filter {
            $0.contentKind == .videoWebM
        }
        guard assignment.units.count == 10,
              Set(assignment.units.map(\.emotionID)).count == 10,
              Set(assignment.units.map(\.emoji)).count == 10,
              staticUnits.count == 7,
              videoUnits.count == 3 else {
            throw Self.error(
                code: 1,
                description: "Avatar sticker assignment must contain 7 static and 3 video units"
            )
        }
        return try assignment.units.map { unit in
            let data = try Data(contentsOf: unit.fileURL)
            guard !data.isEmpty,
                  data.count <= 256 * 1024,
                  unit.width == 512,
                  unit.height == 512 else {
                throw Self.error(
                    code: 1,
                    description: "Avatar sticker file violates Telegram limits"
                )
            }
            let resource = LocalFileMediaResource(
                fileId: Int64.random(in: Int64.min ... Int64.max),
                size: Int64(data.count)
            )
            self.context.account.postbox.mediaBox.storeResourceData(
                resource.id,
                data: data,
                synchronous: true
            )
            return PreparedSticker(
                emoji: unit.emoji,
                sticker: ImportSticker(
                    resource: .standalone(resource: resource),
                    emojis: [unit.emoji],
                    dimensions: PixelDimensions(
                        width: Int32(unit.width),
                        height: Int32(unit.height)
                    ),
                    duration: unit.durationSeconds,
                    mimeType: unit.contentKind == .staticWebP
                        ? "image/webp"
                        : "video/webm",
                    keywords: "avatar_\(unit.emotionID)"
                )
            )
        }
    }

    private func reconciliationOperations(
        currentItems: [StickerPackItem],
        newStickers: [PreparedSticker]
    ) -> [ReconciliationOperation] {
        var currentItemsByEmoji: [String: StickerPackItem] = [:]
        for item in currentItems {
            guard let emoji = Self.stickerEmoji(item.file._parse()),
                  currentItemsByEmoji[emoji] == nil else {
                continue
            }
            currentItemsByEmoji[emoji] = item
        }
        return newStickers.map { preparedSticker in
            if let currentItem = currentItemsByEmoji[preparedSticker.emoji] {
                return .replace(currentItem, preparedSticker.sticker)
            } else {
                return .add(preparedSticker.sticker)
            }
        }
    }

    /// Same title format as Android: "Teamgram Avatar <avatarID>".
    private static func stickerSetTitle(avatarID: Int64) -> String {
        "Teamgram Avatar \(avatarID)"
    }

    /// One Telegram sticker set per avatar: a new avatar creates its own set
    /// (Sticker Bot notification, set inserted at the top of installed packs);
    /// editing an avatar updates that avatar's set in place.
    private func stickerSetShortName(avatarID: Int64) -> String {
        let accountID = UInt64(bitPattern: self.context.account.peerId.toInt64())
        return String(
            format: "sends_avatar_%016llx_%016llx",
            accountID,
            UInt64(bitPattern: avatarID)
        )
    }

    private func importedParamsHash(shortName: String) -> String? {
        UserDefaults.standard.string(forKey: self.paramsHashKey(
            shortName: shortName
        ))
    }

    private func storeImportedParamsHash(
        _ paramsHash: String,
        shortName: String
    ) {
        UserDefaults.standard.set(
            paramsHash,
            forKey: self.paramsHashKey(shortName: shortName)
        )
    }

    private func paramsHashKey(shortName: String) -> String {
        "AvatarIntegration.TelegramStickerPack.\(shortName).paramsHash"
    }

    private static func stickerEmoji(_ file: TelegramMediaFile) -> String? {
        for attribute in file.attributes {
            if case let .Sticker(displayText, _, _) = attribute,
               !displayText.isEmpty {
                return displayText
            }
        }
        return nil
    }

    private static func error(
        code: Int,
        description: String
    ) -> NSError {
        NSError(
            domain: "AvatarTelegramStickerPackAssigner",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }
}

/// Decodes the server-produced Telegram WebM (VP9 + alpha) for the avatar
/// module's sticker panel, with the same FFmpeg path Telegram uses for video
/// stickers. Frame timing comes from the file, so the preview runs at exactly
/// the speed Telegram shows.
enum AvatarTelegramStickerVideoPreviewDecoder {
    private static let maximumFrameCount = 180
    private static let decodingQueue = Queue(
        name: "AvatarIntegration.StickerVideoPreview.Decoding",
        qos: .utility
    )

    static func decode(
        url: URL,
        pixelSize: Int
    ) -> [AvatarStickerVideoPreviewFrame]? {
        var result: [AvatarStickerVideoPreviewFrame]?
        // VideoStickerDirectFrameSource must be created and released on its queue.
        Self.decodingQueue.sync {
            result = Self.decodeOnQueue(url: url, pixelSize: pixelSize)
        }
        return result
    }

    private static func decodeOnQueue(
        url: URL,
        pixelSize: Int
    ) -> [AvatarStickerVideoPreviewFrame]? {
        FFMpegGlobals.initializeGlobals()
        guard pixelSize > 0,
              let frameSource = VideoStickerDirectFrameSource(
                  queue: Self.decodingQueue,
                  path: url.path,
                  isVP9: true,
                  width: pixelSize,
                  height: pixelSize,
                  cachePathPrefix: nil,
                  unpremultiplyAlpha: false
              ) else {
            return nil
        }
        var images: [UIImage] = []
        while images.count < Self.maximumFrameCount,
              let frame = frameSource.takeFrame(draw: true) {
            guard case .argb = frame.type,
                  let image = Self.image(from: frame) else {
                return nil
            }
            images.append(image)
        }
        guard !images.isEmpty else {
            return nil
        }
        let frameDuration: TimeInterval
        if frameSource.duration > 0 {
            frameDuration = frameSource.duration / Double(images.count)
        } else {
            frameDuration = 1.0 / Double(max(1, frameSource.frameRate))
        }
        return images.map {
            AvatarStickerVideoPreviewFrame(image: $0, duration: frameDuration)
        }
    }

    /// Frames are BGRA in memory with straight (non-premultiplied) alpha.
    private static func image(from frame: AnimatedStickerFrame) -> UIImage? {
        guard frame.width > 0,
              frame.height > 0,
              frame.data.count >= frame.bytesPerRow * frame.height,
              let provider = CGDataProvider(data: frame.data as CFData) else {
            return nil
        }
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue)
        )
        guard let cgImage = CGImage(
            width: frame.width,
            height: frame.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: frame.bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
