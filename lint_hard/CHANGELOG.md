# 7.1.0
- added the `throwing_unthrown_exception` lint for `@Throwing` types that are not thrown.
- improved `document_throws_fix` handling for provenance cleanup and doc comment formatting.
- clarified plugin configuration and documentation.

# 7.0.1
- re-ordered the readme so that the install instructions are closer to the top.

# 7.0.0
- implemented new lint: document_thrown_exceptions that warns when a method has not documented a throws clause.
- migrated the code away from custom_lint to the analyzer v9 package.
- UPGRADE: if upgrading from lint_hard 6.x you will need to include a plugin 
declaration in your analysis_options.yaml file to activate the custom lints in
lint_hard.  See the README.md for details.


# 6.2.1
- disabled type_annotate_public_apis as it is incompatible wiht omit_obvious_property_types which I consider the more important lint for most users.
If you are a package maintainer you should re-enable type_annotate_public_apis for your public api's.
# 6.2.0
- added custom lint 'fields_first_constructors_next' which places
 fields before constructors so that the state of a class is 
 at the top and together.

# 6.1.1
- removed unsafe_variance. It's experimental and the suggested fixes
 seem overly complicated and you still have to suppress the warning.

# 6.1.0

Added new lints:
- omit_obvious_property_types
- deprecated_member_use_from_same_package
- unsafe_variance

# 6.0.0
- added 3.7 lints

# 5.0.0
- added new 3.0, 3.1 lints from the linter project

# 4.0.0
- removed prefer_foreach because I prefer a for loop.
- upgraded to dart 3.0

# 3.0.1
moved to stable 2.19

# 3.0.0-beta.4
- removed strong mode as it is deprecaed in favour of the new
- removed implict-casts as its no longer required and has been removed in 3.x

# 3.0.0-beta.2
- disabled no_leading_underscores_for_local_identifiers as its useful
in callbacks that have a parameter we don't want to use.

# 3.0.0-beta.1
- added latest lints from dart 2.19 and upgraded minimum sdk version to 2.19.

# 2.1.1
- improved the readme.
- removed invariant_booleans as it has been deprecated.

# 2.1.0
- Added additional lints for upcomming 2.18 and 2.19 releases.

# 2.0.0
- updated list of lints to support the latest .
- Added discared futures.
- Added copyright notices.
- test for unawaited futures.

# 1.0.4
- added advise for package maintianers.

# 1.0.3
- Added  strict-raw-types: true and strict-inference: true

# 1.0.1
Fixed example analysis_options.yaml

# 1.0.0
Initial release.
