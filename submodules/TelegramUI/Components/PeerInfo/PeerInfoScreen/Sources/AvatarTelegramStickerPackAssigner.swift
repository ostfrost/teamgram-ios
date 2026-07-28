import AccountContext
import AvatarIntegration
import Foundation
import PeerInfoScreen
import Postbox
import SwiftSignalKit
import TelegramCore
import UIKit

public enum AvatarPeerInfoIntegration {
    public static func install() {
        PeerInfoAvatarModuleIntegration.presenter = {
            presentingViewController,
            context,
            localeIdentifier,
            avatarCompletion in
            let stickerPackAssigner = AvatarTelegramStickerPackAssigner(
                context: context
            )

            AvatarIntegrationEntryPoint.presentAvatarFlow(
                from: presentingViewController,
                localeIdentifier: localeIdentifier,
                onStickerPackReady: {
                    [stickerPackAssigner] assignment,
                    completion in
                    stickerPackAssigner.assign(
                        assignment,
                        completion: completion
                    )
                },
                onAvatarCreated: { result in
                    avatarCompletion(result.image)
                }
            )
        }
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
        let shortName = self.stickerSetShortName()
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
                title: "My Avatar Stickers",
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
            guard case let .result(info, items, installed) = loadedPack else {
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

    private func stickerSetShortName() -> String {
        let accountID = UInt64(bitPattern: self.context.account.peerId.toInt64())
        return String(format: "sends_avatar_%016llx", accountID)
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
