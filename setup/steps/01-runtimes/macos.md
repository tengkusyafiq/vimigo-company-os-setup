# Step 1 on macOS

## Before you run anything, say this

If Homebrew is not installed, its installer asks for the login password:

> *"Your Mac will ask for the password you use to log in. It won't show anything
> as you type — that's normal, just type it and press Enter."*

That last sentence matters. People conclude the keyboard is broken and start
over.

## Commands

If `brew --version` fails, install Homebrew first — its own installer prints the
two lines needed to put `brew` on the PATH for Apple Silicon. Run them.

Then install only what is missing:

    brew install node
    brew install git
    brew install python@3.13

Run each in the background and poll.

## After installing

macOS ships a `python3` already, so Python is rarely missing. Git may resolve to
the Xcode command line tools stub, which prompts to install them — that is a GUI
prompt, so warn before it appears.
