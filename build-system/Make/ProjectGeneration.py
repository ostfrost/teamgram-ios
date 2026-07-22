import argparse
import json
import os
import re
import shutil

from BuildEnvironment import is_apple_silicon, call_executable, BuildEnvironment


def remove_directory(path):
    if os.path.isdir(path):
        shutil.rmtree(path)


def _set_build_setting(build_settings, key, value):
    pattern = r'(\n[ \t]*){} = [^;]+;'.format(re.escape(key))
    replacement = r'\1{} = {};'.format(key, value)
    if re.search(pattern, build_settings):
        return re.sub(pattern, replacement, build_settings, count=1)

    end_match = re.search(r'\n([ \t]*)\};\s*$', build_settings)
    if end_match:
        setting_indent = end_match.group(1) + '\t'
        return re.sub(
            r'\n([ \t]*)\};\s*$',
            '\n{}{} = {};\n{}{};'.format(setting_indent, key, value, end_match.group(1), '}'),
            build_settings,
            count=1
        )

    match = re.search(r'\n([ \t]*)([A-Z0-9_]+|"[^"]+") = ', build_settings)
    if match:
        indent = match.group(1)
    else:
        indent = '\t\t\t\t'

    return '{}\n{}{} = {};'.format(build_settings.rstrip(), indent, key, value)


def _scheme_references_xcodeproj(contents, xcodeproj_path):
    normalized_path = xcodeproj_path.replace(os.sep, '/')
    project_name = os.path.basename(normalized_path)
    return (
        normalized_path in contents
        or 'container:{}'.format(project_name) in contents
        or 'container:{}'.format(normalized_path) in contents
    )


def _find_app_scheme_path(scheme_dir, xcodeproj_path, target_name):
    target_basename = target_name.split('/')[-1]
    exact_scheme_path = os.path.join(scheme_dir, '{}.xcscheme'.format(target_basename))
    scheme_paths = []

    if os.path.isfile(exact_scheme_path):
        scheme_paths.append(exact_scheme_path)

    if os.path.isdir(scheme_dir):
        for file_name in sorted(os.listdir(scheme_dir)):
            if not file_name.endswith('.xcscheme'):
                continue
            candidate_path = os.path.join(scheme_dir, file_name)
            if candidate_path not in scheme_paths:
                scheme_paths.append(candidate_path)

    fallback_paths = []
    for scheme_path in scheme_paths:
        with open(scheme_path, 'r') as file:
            contents = file.read()
        if not re.search(r'BuildableName = "[^"]+\.app"', contents):
            continue
        if not _scheme_references_xcodeproj(contents, xcodeproj_path):
            continue
        if 'BlueprintName = "{}"'.format(target_basename) in contents:
            return scheme_path
        fallback_paths.append(scheme_path)

    if fallback_paths:
        return fallback_paths[0]
    return None


def _assert_app_store_archive_scheme(contents, scheme_path):
    if not re.search(
        r'<BuildActionEntry\b[\s\S]*?buildForArchiving = "YES"[\s\S]*?<BuildableReference\b[\s\S]*?BuildableName = "[^"]+\.app"',
        contents
    ):
        raise RuntimeError(
            '{} must build the app target for archiving'.format(scheme_path)
        )
    if not re.search(
        r'<ArchiveAction\b[\s\S]*?buildConfiguration = "Release"',
        contents
    ):
        raise RuntimeError(
            '{} must archive with the Release configuration'.format(scheme_path)
        )


def _assert_app_store_archive_project_settings(contents, target_name, project_path):
    target_basename = target_name.split('/')[-1]
    found_app_settings = False

    for match in re.finditer(
        r'buildSettings = \{.*?\n[ \t]*\};',
        contents,
        flags=re.DOTALL
    ):
        build_settings = match.group(0)
        is_app_product = re.search(
            r'BAZEL_OUTPUTS_PRODUCT_BASENAME = ("[^"]+\.app"|[^;]+\.app);',
            build_settings
        )
        is_requested_target = (
            'COMPILE_TARGET_NAME = {};'.format(target_basename) in build_settings
            or 'BAZEL_LABEL = "@@//{0}:{0}";'.format(target_basename) in build_settings
        )
        if not is_app_product or not is_requested_target:
            continue

        found_app_settings = True
        if not re.search(r'\n[ \t]*INSTALL_PATH = /Applications;', build_settings):
            raise RuntimeError(
                '{} must install the app target into /Applications for archives'.format(project_path)
            )
        if not re.search(r'\n[ \t]*SKIP_INSTALL = NO;', build_settings):
            raise RuntimeError(
                '{} must set SKIP_INSTALL = NO for the app target'.format(project_path)
            )
        if not re.search(r'\n[ \t]*IPHONEOS_DEPLOYMENT_TARGET = 17\.0;', build_settings):
            raise RuntimeError(
                '{} must set iOS 17.0 only for the app target'.format(project_path)
            )

    if not found_app_settings:
        raise RuntimeError(
            '{} does not contain archive settings for {}'.format(project_path, target_basename)
        )


def configure_app_store_archive_for_generated_project(base_path, xcodeproj_path, target_name):
    scheme_dir = os.path.join(
        base_path,
        xcodeproj_path,
        'xcshareddata',
        'xcschemes'
    )
    scheme_path = _find_app_scheme_path(scheme_dir, xcodeproj_path, target_name)
    if scheme_path is None:
        if target_name == 'Telegram':
            raise RuntimeError(
                'Could not find an app xcscheme in {}'.format(scheme_dir)
            )
        return

    current_mode = os.stat(scheme_path).st_mode
    os.chmod(scheme_path, current_mode | 0o200)

    with open(scheme_path, 'r') as file:
        contents = file.read()

    contents = contents.replace(
        'buildForArchiving = "NO"',
        'buildForArchiving = "YES"'
    )
    contents = re.sub(
        r'(<ArchiveAction\s+buildConfiguration = )"[^"]+"',
        r'\1"Release"',
        contents,
        count=1
    )
    _assert_app_store_archive_scheme(contents, scheme_path)

    with open(scheme_path, 'w') as file:
        file.write(contents)

    project_path = os.path.join(base_path, xcodeproj_path, 'project.pbxproj')
    if not os.path.isfile(project_path):
        return

    current_mode = os.stat(project_path).st_mode
    os.chmod(project_path, current_mode | 0o200)

    with open(project_path, 'r') as file:
        contents = file.read()

    def update_build_settings(match):
        build_settings = match.group(0)
        target_basename = target_name.split('/')[-1]
        is_app_product = re.search(
            r'BAZEL_OUTPUTS_PRODUCT_BASENAME = ("[^"]+\.app"|[^;]+\.app);',
            build_settings
        )
        is_requested_target = (
            'COMPILE_TARGET_NAME = {};'.format(target_basename) in build_settings
            or 'BAZEL_LABEL = "@@//{0}:{0}";'.format(target_basename) in build_settings
        )
        if is_app_product and is_requested_target:
            build_settings = _set_build_setting(build_settings, 'INSTALL_PATH', '/Applications')
            build_settings = _set_build_setting(build_settings, 'SKIP_INSTALL', 'NO')
            build_settings = _set_build_setting(build_settings, 'IPHONEOS_DEPLOYMENT_TARGET', '17.0')
            if re.search(r'\n[ \t]*BAZEL_OUTPUTS_PRODUCT = "bazel-out/[^"]+-opt-', build_settings):
                build_settings = _set_build_setting(build_settings, 'CODE_SIGN_IDENTITY', '"Apple Distribution"')
                build_settings = _set_build_setting(build_settings, '"CODE_SIGN_IDENTITY[sdk=iphoneos*]"', '"Apple Distribution"')
            return build_settings

        return _set_build_setting(build_settings, 'SKIP_INSTALL', 'YES')

    contents = re.sub(
        r'buildSettings = \{.*?\n[ \t]*\};',
        update_build_settings,
        contents,
        flags=re.DOTALL
    )
    _assert_app_store_archive_project_settings(contents, target_name, project_path)

    with open(project_path, 'w') as file:
        file.write(contents)


def generate_xcodeproj(build_environment: BuildEnvironment, disable_extensions, disable_provisioning_profiles, include_release, generate_dsym, bazel_app_arguments, target_name):
    if '/' in target_name:
        app_target_spec = target_name.split('/')[0] + '/' + target_name.split('/')[1] + ':' + target_name.split('/')[1]
        app_target = target_name
        app_target_clean = app_target.replace('/', '_')
    else:
        app_target_spec = '{target}:{target}'.format(target=target_name)
        app_target = target_name
        app_target_clean = app_target.replace('/', '_')

    bazel_generate_arguments = [build_environment.bazel_path]

    bazel_generate_arguments += ['run', '//{}_xcodeproj'.format(app_target_spec)]

    if target_name == 'Telegram':
        if disable_extensions:
            bazel_generate_arguments += ['--//{}:disableExtensions'.format(app_target)]
        bazel_generate_arguments += ['--//{}:disableStripping'.format(app_target)]

    project_bazel_arguments = []
    for argument in bazel_app_arguments:
        project_bazel_arguments.append(argument)

    if target_name == 'Telegram':
        if disable_extensions:
            project_bazel_arguments += ['--//{}:disableExtensions'.format(app_target)]
        project_bazel_arguments += ['--//{}:disableStripping'.format(app_target)]

    project_bazel_arguments += ['--features=-swift.debug_prefix_map']
    project_bazel_arguments += ['--features=swift.emit_swiftsourceinfo']
    
    xcodeproj_bazelrc = os.path.join(build_environment.base_path, 'xcodeproj.bazelrc')
    if os.path.isfile(xcodeproj_bazelrc):
        os.unlink(xcodeproj_bazelrc)
    with open(xcodeproj_bazelrc, 'w') as file:
        for argument in project_bazel_arguments:
            file.write('build ' + argument + '\n')

    call_executable(bazel_generate_arguments)

    xcodeproj_path = '{}.xcodeproj'.format(app_target_spec.replace(':', '/'))
    configure_app_store_archive_for_generated_project(build_environment.base_path, xcodeproj_path, target_name)
    return xcodeproj_path


def generate(build_environment: BuildEnvironment, disable_extensions, disable_provisioning_profiles, include_release, generate_dsym, bazel_app_arguments, target_name) -> str:
    return generate_xcodeproj(build_environment, disable_extensions, disable_provisioning_profiles, include_release, generate_dsym, bazel_app_arguments, target_name)


def _main():
    parser = argparse.ArgumentParser(
        description='Configure a generated Xcode project for App Store archives.'
    )
    parser.add_argument('--base-path', required=True)
    parser.add_argument('--xcodeproj-path', required=True)
    parser.add_argument('--target-name', required=True)
    arguments = parser.parse_args()
    configure_app_store_archive_for_generated_project(
        arguments.base_path,
        arguments.xcodeproj_path,
        arguments.target_name
    )


if __name__ == '__main__':
    _main()
