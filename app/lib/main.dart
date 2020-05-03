import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:todo_app/navigation.dart';
import 'package:todo_app/history/history_page.dart';
import 'package:todo_app/task_list/task_list.dart';
import 'package:todo_app/user_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class Env {
  Env({@required this.baseUrl})
      : assert(
          baseUrl != null,
          'this app needs a server',
        ),
        assert(
          !baseUrl.path.endsWith('/graphql'),
          'baseUrl was incorrectly passed a /graphql endpoint',
        );

  final Uri baseUrl;

  String get graphqlEndpoint => baseUrl.resolve('/graphql').toString();

  static Env get global => Env(
        baseUrl: Uri.parse(DotEnv().env['APP_BASE_URL']),
      );
}

void main() async {
  await WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await DotEnv().load('.env');
  runApp(App());
}

class App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ValueNotifier<GraphQLClient> client = ValueNotifier<GraphQLClient>(
      GraphQLClient(
        cache: OptimisticCache(
          dataIdFromObject: typenameDataIdFromObject,
        ),
        link: googleSignInLink.concat(
          HttpLink(
            uri: Env.global.graphqlEndpoint,
            headers: {"Accept": "application/json"},
          ),
        ),
      ),
    );
    return GraphQLProvider(
      client: client,
      child: CacheProvider(
        child: MaterialApp(
          title: 'Flutter Demo',
          theme: ThemeData(
            primarySwatch: Colors.blue,
          ),
          home: AuthenticationProvider(
            child: SafeArea(
              maintainBottomViewPadding: true,
              child: ControlledTabView(children: [
                TaskList(),
                TaskHistory(),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
