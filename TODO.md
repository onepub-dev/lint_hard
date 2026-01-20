- [] add an option to the analysis_options that allows the user
to disable exceptions that derive from the Error class.

The dt-fix tool should also support a command line that controls this.
Though it would be nice if the dt-fix tool took its default actions
from the analysis_options.yaml with the option to override that 
behaviour with a cli switch for dt-fix.


- [] I'm testing lint_hard from the ~/git/dcli/dcli package.
It has lint_hard enabled in the analysis_options.yaml bu tthe analysis
server insights says that no plugins are enabled.
