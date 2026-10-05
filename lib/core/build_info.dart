/// The short git SHA this build was made from.
///
/// Release and CI builds pass it in with
/// `--dart-define=GIT_SHA=$(git rev-parse --short HEAD)`; anything built
/// without it (a plain `flutter run`, the test suite) reads `dev`. Shown at
/// the foot of Settings so a device check can name the exact build it saw.
const kGitSha = String.fromEnvironment('GIT_SHA', defaultValue: 'dev');
