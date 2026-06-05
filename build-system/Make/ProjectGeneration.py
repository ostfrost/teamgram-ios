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

def configure_app_store_archive_for_generated_project(base_path, xcodeproj_path, target_name):
    scheme_dir = os.path.join(
        base_path,
        xcodeproj_path,
        'xcshareddata',
        'xcschemes'
    )
    scheme_path = os.path.join(scheme_dir, '{}.xcscheme'.format(target_name.split('/')[-1]))
    if not os.path.isfile(scheme_path):
        scheme_path = None
        if os.path.isdir(scheme_dir):
            for file_name in sorted(os.listdir(scheme_dir)):
                if not file_name.endswith('.xcscheme'):
                    continue
                candidate_path = os.path.join(scheme_dir, file_name)
                with open(candidate_path, 'r') as file:
                    candidate_contents = file.read()
                if (
                    re.search(r'BuildableName = "[^"]+\.app"', candidate_contents)
                    and 'BlueprintName = "{}"'.format(target_name.split('/')[-1]) not in candidate_contents
                    and xcodeproj_path in candidate_contents
                ):
                    scheme_path = candidate_path
                    break
        if scheme_path is None:
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
        if (
            re.search(r'BAZEL_OUTPUTS_PRODUCT_BASENAME = ("[^"]+\.app"|[^;]+\.app);', build_settings)
            and 'COMPILE_TARGET_NAME = {};'.format(target_name.split('/')[-1]) in build_settings
        ):
            build_settings = _set_build_setting(build_settings, 'INSTALL_PATH', '/Applications')
            if re.search(r'\n[ \t]*BAZEL_OUTPUTS_PRODUCT = "bazel-out/[^"]+-opt-', build_settings):
                build_settings = _set_build_setting(build_settings, 'CODE_SIGN_IDENTITY', '"Apple Distribution"')
                build_settings = _set_build_setting(build_settings, '"CODE_SIGN_IDENTITY[sdk=iphoneos*]"', '"Apple Distribution"')
            return build_settings

        if re.search(r'BAZEL_OUTPUTS_PRODUCT_BASENAME = [^;]+\.framework;', build_settings):
            return _set_build_setting(build_settings, 'SKIP_INSTALL', 'YES')

        return build_settings

    contents = re.sub(
        r'buildSettings = \{.*?\n[ \t]*\};',
        update_build_settings,
        contents,
        flags=re.DOTALL
    )

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
