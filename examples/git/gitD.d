import std.stdio;
import std.string;
import std.algorithm;
import std.file;
import std.path;
import std.process;
import std.c.stdlib;

import docopt;

static auto doc = "
usage: git [--version] [--exec-path=<path>] [--html-path]
           [-p|--paginate|--no-pager] [--no-replace-objects]
           [--bare] [--git-dir=<path>] [--work-tree=<path>]
           [-c <name>=<value>] [--help]
           <command> [<args>...]

options:
    -c <name=value>
    -h, --help
    -p, --paginate

The most commonly used git commands are:
   add        Add file contents to the index
   branch     List, create, or delete branches
   checkout   Checkout a branch or paths to the working tree
   clone      Clone a repository into a new directory
   commit     Record changes to the repository
   push       Update remote refs along with associated objects
   remote     Manage set of tracked repositories

See 'git help <command>' for more information on a specific command.

";

int main(string[] argv) {
    string baseDir = dirName(absolutePath(argv[0]));

    bool help = true;
    bool optionsFirst = true;
    auto parsed = docopt.docopt(doc, argv[1..$], help, "git version 1.7.4.4",
                                optionsFirst);

    auto cmds = ["add", "branch", "checkout", "clone", "commit",
                 "push", "remote"];

    writeln("global arguments");
    writeln(prettyPrintArgs(parsed));
    writeln("command arguments");

    string command = parsed["<command>"].toString;
    string[] newArgv = [command] ~ parsed["<args>"].asList;

    if (canFind(cmds, command)) {
        string cmd = buildNormalizedPath(baseDir, format("git_%s", command));
        auto res = execute([cmd] ~ newArgv);
        writeln(res.output);
        return res.status;
    } else if (command == "help") {
        string helpCmd;
        string[] helpArgs;
        string[] subCmds = parsed["<args>"].asList;
        if (subCmds.length > 0 && canFind(cmds, subCmds)) {
            helpCmd = buildNormalizedPath(baseDir, format("git_%s", subCmds[0]));
            helpArgs = [helpCmd, newArgv[0], "--help"];
        } else {
            helpCmd = absolutePath(argv[0]);
            helpArgs = [helpCmd, "--help"];
        }
        auto res = execute(helpArgs);
        writeln(res.output);
        return res.status;
    } else {
        writeln(format("%s is not a gitD command.", command));
        return 1;
    }

    return 0;
}