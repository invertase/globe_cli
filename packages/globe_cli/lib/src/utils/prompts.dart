import 'dart:io';

import 'package:get_it/get_it.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';

import '../exit.dart';
import 'api.dart';
import 'auth.dart';
import 'env.dart';
import 'project_settings.dart';
import 'scope.dart';

/// Prompts the user to link the current local project to a Globe project.
///
/// This creates a `dart_globe/project.json` file in the `.dart_tool` directory
/// which is used to determine the current project scope.
Future<ScopeMetadata> linkProject({
  required Logger logger,
  required GlobeApi api,
  Organization? org,
}) async {
  try {
    final organization =
        org ?? await selectOrganization(logger: logger, api: api);

    final project = await selectProject(
      organization,
      logger: logger,
      api: api,
    );

    final result = GetIt.I<GlobeScope>().setScope(
      ScopeMetadata(
        orgId: organization.id,
        projectId: project.id,
        projectSlug: project.slug,
      ),
    );

    final projectUrl = Uri.parse(api.metadata.endpoint)
        .replace(path: '/${organization.slug}/${project.slug}')
        .toString();

    logger.success('''
  Successfully linked project. View your project on Globe: ${cyan.wrap(projectUrl)}',
''');
    logger.write(
      '   To unlink this project in the future run: ${cyan.wrap('globe unlink')}\n',
    );

    return result;
  } on ApiException catch (e) {
    logger.err(e.message);
    exitOverride(1);
  } catch (e) {
    logger.err(e.toString());
    exitOverride(1);
  }
}

/// Prompts the user to select an organization they are a member of.
///
/// If the user is only a memeber of 1, it will automatically be selected.
Future<Organization> selectOrganization({
  required Logger logger,
  required GlobeApi api,
  void Function()? onNoOrganizationsError,
}) async {
  logger.detail('Fetching user organizations');
  final organizations = await api.getOrganizations();
  logger.detail('Found ${organizations.length} organizations');

  if (organizations.isEmpty) {
    if (onNoOrganizationsError == null) {
      logger.detail(
        'No organizations found, this is likely a new account which is still being setup. Please try again in a few seconds.',
      );
      logger.err('Your account is still being setup, please try again.');
    } else {
      onNoOrganizationsError.call();
    }
    exitOverride(1);
  }

  /// If there's only one, automatically select it.
  if (organizations.length == 1) {
    final organization = organizations.first;
    logger.detail('Automatically selecting ${organization.name}.');
    return organization;
  }

  // Otherwise let the user select one.
  final selectedOrg = logger.chooseOne(
    'Please select an organization:',
    choices: organizations.map((o) => o.id).toList(),
    display: (choice) => organizations.firstWhere((o) => o.id == choice).name,
  );

  return organizations.firstWhere((o) => o.id == selectedOrg);
}

/// Prompts the user to select a project they have access to, in the provided
/// [organization].
Future<Project> selectProject(
  Organization organization, {
  required Logger logger,
  required GlobeApi api,
  String message = '❓ Please select a project you want to link:',
}) async {
  logger.detail('Fetching organization projects');

  final projects = await api.getProjects(org: organization.id);
  logger.detail('Found ${projects.length} projects');

  String selectRootDirectory() {
    final rootDirectory = logger.prompt(
      '❓ Specify which directory your project is in:',
      defaultValue: './',
    );

    if (rootDirectory.contains('..')) {
      logger.info(
        red.wrap(
          ' The root directory cannot be a parent directory, please try again.',
        ),
      );
      return selectRootDirectory();
    }

    final directory = Directory(
      p.join(Directory.current.path, rootDirectory),
    );

    if (!directory.existsSync()) {
      logger.info(
        red.wrap(
          '   The directory "$rootDirectory" does not exist, please try again.',
        ),
      );
      return selectRootDirectory();
    }

    return rootDirectory;
  }

  Future<Project> createProject() async {
    final rootDirectory = selectRootDirectory();
    final rootDirectoryDir = Directory(rootDirectory);

    final pubspecFile = File(
      p.join(rootDirectoryDir.absolute.path, 'pubspec.yaml'),
    );

    if (!pubspecFile.existsSync()) {
      logger.info(
        red.wrap(
          '   The directory "$rootDirectory" does not contain a pubspec.yaml file, please try again.',
        ),
      );
      return createProject();
    }

    final pubspecContent = pubspecFile.readAsStringSync();
    final parsed = Pubspec.parse(pubspecContent);

    final name = logger.prompt(
      '❓ Enter the name of the project:',
      defaultValue: parsed.name,
    );

    final (discoveredPreset, entryPoints) = await (
      api.discoverPreset(pubspecContent),
      findMainEntryPoint(rootDirectoryDir)
    ).wait;

    String? buildCommand;
    String? entrypoint;

    if (entryPoints.isNotEmpty) {
      entrypoint = switch (entryPoints.length) {
        1 => entryPoints.first,
        > 1 => logger.chooseOne(
            '❓ Choose Dart entrypoint file:',
            choices: entryPoints,
          ),
        _ => null,
      };
      logger.detail('Using entry point in `$entrypoint`');
    }

    if (discoveredPreset != null) {
      logger.detail('Detected "${discoveredPreset.name}" preset');
      if (discoveredPreset.buildCommand != null) {
        buildCommand = discoveredPreset.buildCommand;
        logger.detail('Using preset build command: `$buildCommand`');
      }

      if (discoveredPreset.entrypoint.isNotEmpty && entrypoint == null) {
        entrypoint = discoveredPreset.entrypoint;
        logger.detail('Using preset entry point: `$entrypoint`');
      }
    }

    // Check if project has build_runner, if not skip.
    const buildRunner = 'build_runner';
    if (parsed.devDependencies.keys.any((p) => p == buildRunner) ||
        parsed.dependencies.keys.any((p) => p == buildRunner)) {
      if (logger.confirm('❓ Would you like to run a custom build command?')) {
        buildCommand = logger.prompt(
          '❓ Enter a build command:',
          defaultValue: buildCommand,
        );
      }
    }

    final envVarFile = File(
      p.join(rootDirectoryDir.absolute.path, '.env'),
    );

    Map<String, String>? environmentVariables;

    if (envVarFile.existsSync()) {
      final uploadEnvVars = logger.chooseOne(
        '❓ An .env file was detected, would you like to:',
        choices: ['ignore', 'upload', 'modify'],
        display: (choice) {
          switch (choice) {
            case 'ignore':
              return 'Ignore local environment variables';
            case 'upload':
              return 'Upload local environment variables';
            case 'modify':
              return 'Upload environment variables with new values';
          }

          throw ArgumentError.value(choice, 'choice', 'Invalid choice');
        },
        defaultValue: 'ignore',
      );

      if (uploadEnvVars == 'upload') {
        environmentVariables = getEnvironmentVariables(envVarFile);
      }

      if (uploadEnvVars == 'modify') {
        getEnvironmentVariables(envVarFile).forEach((key, value) {
          final newValue = logger.prompt(
            '❓ Enter a value for "$key":',
            defaultValue: value,
          );

          environmentVariables ??= {};
          environmentVariables![key] = newValue;
        });
      }
    }

    final project = await api.createProject(
      orgId: organization.id,
      name: name,
    );

    await api.updateSettings(
      projectId: project.id,
      orgId: project.orgId,
      settings: ProjectSettings(
        rootDirectory: rootDirectory == './' ? null : rootDirectory,
        preset: discoveredPreset?.id,
        buildCommand: buildCommand,
        entrypoint: entrypoint,
        environmentVariables: environmentVariables,
      ),
    );

    return project;
  }

  if (projects.isEmpty) {
    logger.detail('No projects found, prompting to create a new project');
    return createProject();
  }

  const createSymbol = '__CREATE_PROJECT';

  // Select a project or create a new one.
  final selectedProject = logger.chooseOne(
    message,
    choices: [
      if (api.auth.currentSession?.authenticationMethod !=
          AuthenticationMethod.apiToken)
        createSymbol,
      ...projects.map((p) => p.id),
    ],
    display: (choice) {
      if (choice == createSymbol) {
        return 'Create a new project';
      }

      return projects.firstWhere((p) => p.id == choice).slug;
    },
  );

  // If the user selected to create a new project, prompt to create one.
  if (selectedProject == createSymbol) {
    return createProject();
  }

  return projects.firstWhere((p) => p.id == selectedProject);
}

/// Prompts the user to select single or multiple projects.
///
/// Optionally pass [ids] to only verify projects Ids actually exist
Future<List<Project>> selectProjects(
  String question,
  Organization organization, {
  required Logger logger,
  required GlobeApi api,
  required GlobeScope scope,
  List<String>? ids,
}) async {
  logger.detail('Fetching organization projects');
  final projects = await api.getProjects(org: organization.id);
  logger.detail('Found ${projects.length} projects');

  if (projects.isEmpty) {
    logger.detail(
      'No projects found, you need to create a new project first.',
    );
    logger.err('No projects found.');
    exitOverride(1);
  }

  /// If ids passed, verify they exist
  if (ids != null && ids.isNotEmpty) {
    final projectsById = projects
        .fold<Map<String, Project>>({}, (prev, curr) => prev..[curr.id] = curr);
    final invalidIds = ids.where((id) => projectsById[id] == null);
    if (invalidIds.isNotEmpty) {
      logger.err('Project not found: ${cyan.wrap(invalidIds.join(', '))}.');
      exitOverride(1);
    }
    return ids.map((id) => projectsById[id]!).toList();
  }

  /// If there's only one, automatically select it.
  if (projects.length == 1) {
    final project = projects.first;
    logger.detail('Automatically selecting ${project.slug}.');
    return projects;
  }

  final projectsBySlug = projects
      .fold<Map<String, Project>>({}, (prev, curr) => prev..[curr.slug] = curr);

  final projectChoices = projectsBySlug.keys.toList();
  projectChoices.insert(0, 'All projects');

  /// Ask user to choose zero or more options.
  final selections = logger.chooseAny(
    '❓ $question',
    choices: projectChoices,
  );

  if (selections.contains('All projects')) {
    logger.detail('All projects selected.');
    return projects;
  }

  if (selections.isEmpty) {
    logger.detail(
      'No projects selected, you need to select atleast one project.',
    );
    logger.err('No projects selected.');
    exitOverride(1);
  }

  return selections.map((e) => projectsBySlug[e]!).toList();
}

/// Asynchronously finds the main entry points of a Dart project.
/// Returns a list of entry points relative to [rootDir].
Future<List<String>> findMainEntryPoint(Directory rootDir) async {
  final entryPoints = <String>[];

  await for (final entity in rootDir.list(recursive: true)) {
    if (entity is! File) continue;

    final relativePath = p.relative(entity.path, from: rootDir.path);
    final segments = p.split(relativePath);

    if (p.extension(entity.path) != '.dart' ||
        ['.dart_tool', '.fvm', 'test'].any(segments.contains) ||
        p.basename(entity.path).startsWith('test_')) {
      continue;
    }

    final contents = await entity.readAsString();
    if (RegExp(r'\bmain\s*\([^)]*\)').hasMatch(contents)) {
      entryPoints.add(relativePath.replaceAll(r'\', '/'));
    }
  }

  return entryPoints;
}
