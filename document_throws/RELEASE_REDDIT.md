Title: document_throws pre-release: looking for testers

Hi r/dart,

I built a new experimental package that attempts to plug what I think is a
major hole in the Dart ecosystem.

Dart does not have checked exceptions (let's not get into a debate about that),
which makes it difficult to determine what exceptions you might have to
handle when calling a method.

The Dart style guide recommends that developers document these exceptions
in the method documentation using a comment such as /// throws FooException

The problem is that these comments are mostly missing, even from the Dart SDK.

The comments are also inherently difficult to maintain because it's not just
the exceptions that the current method throws but any exceptions thrown
by any method it calls, all the way down through third party packages
and the Dart SDK.

So the document_throws package looks to automate the documentation of throws.

You can read the details at: https://onepub.dev/blogs/

I'm looking for a few willing guinea pigs to give it a try and provide feedback.

It's still fairly rough but is feature complete.

It consists of a linter and CLI tooling (written in Dart).


If you’re willing to try it, please run it against your codebase and share:
- Any crashes or incorrect results
- Cases where the output isn’t what you expect
- Performance notes (large repos, monorepos, CI)
- usability issues

I’ll follow up on issues and fixes quickly. The project is sponsored by OnePub.dev, a private Dart package repository.

Thanks for any help, and feel free to ask questions or suggest improvements.
