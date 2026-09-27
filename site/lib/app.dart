import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';

import 'content/catalog.dart';
import 'content/markdown_doc.dart';
import 'pages/home.dart';

/// Root app — multi-page Router for static generation.
/// Not annotated @client: markdown is read from disk at build time, and the
/// route list itself is generated from the docs sources (see catalog.dart).
class App extends StatelessComponent {
  const App({super.key});

  @override
  Component build(BuildContext context) {
    return Router(
      routes: [
        Route(path: '/', builder: (_, _) => const HomePage()),
        for (final page in docPages)
          Route(
            path: page.route,
            builder: (_, _) => MarkdownDocPage(route: page.route),
          ),
      ],
    );
  }
}
