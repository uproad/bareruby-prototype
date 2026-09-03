# The first stage

Every pass from Prism to C++, the intermediate representations between them, the language
runtime that lands beside the generated source, and the vocabulary a composition is
spelled in. It carries exactly one binding — the one that needs no hardware — and will
never carry another: the moment it reached for the half that runs a second stage, the two
gems would depend on each other and the first stage would stop being loadable on its own.

`Peripheral.register` is what a standard class calls to say what a program may say to it
and what those calls lower to. Nothing here names any of those classes; they are found
because they are installed.
