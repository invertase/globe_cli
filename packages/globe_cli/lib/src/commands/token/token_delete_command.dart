import 'dart:async';

import 'package:mason_logger/mason_logger.dart';

import '../../command.dart';
import '../../utils/api.dart';

class TokenDeleteCommand extends BaseGlobeCommand {
  TokenDeleteCommand() {
    argParser.addOption(
      'tokenId',
      mandatory: true,
      help: 'Specify globe auth token to delete.',
    );
  }
  @override
  String get description => 'Delete globe auth token.';

  @override
  String get name => 'delete';

  @override
  FutureOr<int> run() async {
    requireAuth();

    final tokenId = argResults?['tokenId'] as String;
    final validated = await scope.validate();

    final deleteTokenProgress =
        logger.progress('Deleting Token: ${cyan.wrap(tokenId)}');

    try {
      await api.deleteToken(
        orgId: validated.organization.slug,
        tokenId: tokenId,
      );
      deleteTokenProgress.complete('Token deleted');
    } on ApiException catch (e) {
      deleteTokenProgress.fail('✗ Failed to delete token: ${e.message}');
      return ExitCode.software.code;
    } catch (e, s) {
      deleteTokenProgress.fail('✗ Failed to delete token: $e');
      logger.detail(s.toString());
      return ExitCode.software.code;
    }

    return 0;
  }
}
