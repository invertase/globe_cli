import 'dart:async';

import 'package:mason_logger/mason_logger.dart';

import '../../command.dart';
import '../../utils/api.dart';

class ProjectPauseCommand extends BaseGlobeCommand {
  @override
  String get description => 'Pause the current globe project';

  @override
  String get name => 'pause';

  @override
  FutureOr<int> run() async {
    requireAuth();

    if (!scope.hasScope()) {
      logger.err('Not a Globe project.');
    }

    final validated = await scope.validate();
    final projectSlug = validated.project.slug;
    final pauseProjectProgress =
        logger.progress('Pausing project: ${cyan.wrap(projectSlug)}');

    try {
      await api.pauseProject(
        orgId: validated.organization.id,
        projectId: validated.project.id,
      );

      pauseProjectProgress
          .complete('Your project: ${cyan.wrap(projectSlug)} is now paused');
      return ExitCode.success.code;
    } on ApiException catch (e) {
      pauseProjectProgress.fail('✗ Failed to pause project: $e');
      return ExitCode.software.code;
    } catch (e, s) {
      pauseProjectProgress.fail('✗ Failed to pause project: $e');
      logger.detail(s.toString());
      return ExitCode.software.code;
    }
  }
}
