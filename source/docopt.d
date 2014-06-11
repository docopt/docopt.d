import std.stdio;
import std.regex;
import std.string;
import std.array;
import std.algorithm;
import std.container;
import std.traits;
import std.ascii;
import std.conv;

import argvalue;
import patterns;
import tokens;

private Option parseOption(string optionDescription) {
    string shortArg = null;
    string longArg = null;
    uint argCount = 0;
    string value = null;

    auto parts = split(strip(optionDescription), "  ");
    string options = parts[0];
    string description = "";
    if (parts.length > 1) {
        description = parts[1];
    }
    options = replace(options, ",", " ");
    options = replace(options, "=", " ");
    foreach(s; split(options)) {
        if (startsWith(s, "--")) {
            longArg = s;
        } else if (startsWith(s, "-")) {
            shortArg = s;
        } else {
            argCount = 1;
        }
    }
    if (argCount > 0) {
        auto pat = regex(r"\[default: (.*)\]", "i");
        auto match = matchAll(description, pat);
        if (!match.empty()) {
            value = match.captures[1];
        }
    }

    if (value is null) {
        return new Option(shortArg, longArg, argCount, new ArgValue("false"));
    } else {
        return new Option(shortArg, longArg, argCount, new ArgValue(value));
    }
}

private Option[] parseDefaults(string doc) {
    Option[] defaults;
    foreach(sect; parseSection("options:", doc)) {
        auto s = sect[indexOf(sect, ":")+1..$];
        auto pat = regex(r"\n[ \t]*(-\S+?)");
        auto parts = split('\n'~s, pat)[1..$];
        auto match = array(matchAll('\n'~s, pat));
        foreach(i, m; match) {
            string optionDescription = m[1] ~ parts[i];
            if (startsWith(optionDescription, "-")) {
                defaults ~= parseOption(optionDescription);
            }
        }
    }
    return defaults;
}

private string[] parseSection(string name, string doc) {
    string[] res;
    auto p = regex("^([^\n]*" ~ name ~ "[^\n]*\n?(?:[ \t].*?(?:\n|$))*)", "im");
    auto match = array(matchAll(doc, p));
    foreach (i, m; match) {
        res ~= strip(m[0]);
    }
    return res;
}

private string formalUsage(string section) {
    auto s = section[indexOf(section, ":")+1..$];
    auto parts = split(s);
    string[] subs;
    foreach(part; parts[1..$]) {
        if (part == parts[0]) {
            subs ~= ") | (";
        } else {
            subs ~= part;
        }
    }
    return "( " ~ join(subs, " ") ~ " )";
}

private Pattern[] parseLong(Tokens tokens, ref Option[] options) {
    auto parts = tokens.move().split("=");
    string longArg = parts[0];
    assert(startsWith(longArg, "--"));
    string value = null;

    if (parts.length > 1) {
        value = parts[1];
    }

    Option[] similar;
    foreach (o; options) {
        if (o._longArg == longArg) {
            similar ~= o;
        }
    }
    if (similar.length == 0) {
        foreach (o; options) {
            if (o._longArg && startsWith(o._longArg, longArg)) {
                similar ~= o;
            }
        }
    }

    Option o;

    if (similar.length > 1) {
        writeln(format("%s is not a unique prefix: %s?", longArg, similar));
        assert(false);
    } else if (similar.length < 1) {
        uint argCount = 0;
        if (parts.length > 1) {
            argCount = 1;
        }
        o = new Option(null, longArg, argCount);
        options = options ~ o;

        if (tokens._error == "DocoptExit") {
            if (value == null) {
                o = new Option(null, longArg, argCount, new ArgValue("true"));
            } else {
                o = new Option(null, longArg, argCount, new ArgValue(value));
            }
        }
    } else {
        o = new Option(similar[0]._shortArg, similar[0]._longArg, similar[0]._argCount, similar[0]._value);
        if (o._argCount == 0) {
            if (value != null) {
                writeln(format("%s must not have an argument.", o._longArg));
                assert(false);
            }
        } else {
            if (value == null) {
                if (tokens.current() == null || tokens.current() == "--") {
                    writeln(format("%s requires argument.", o._longArg));
                    assert(false);
                }
                value = tokens.move();
            }
        }
        if (tokens._error == "DocoptExit") {
            if (value == null) {
                o.setValue(new ArgValue("true"));
            } else {
                o.setValue(new ArgValue(value));
            }
        }
    }
    return [o];
}

private Pattern[] parseShort(Tokens tokens, ref Option[] options) {
    string token = tokens.move();
    assert(startsWith(token, "-") && !startsWith(token, "--"));
    string left = stripLeft(token, '-');

    Pattern[] parsed;
    while (left != "") {
        string shortArg = "-" ~ left[0];
        left = left[1..$];

        Option[] similar;
        foreach (o; options) {
            if (o._shortArg == shortArg) {
                similar ~= o;
            }
        }
        Option o;
        if (similar.length > 1) {
            writeln(format("%s is specified ambiguously %d times", shortArg, similar.length));
            assert(false);
        } else if (similar.length < 1) {
            o = new Option(shortArg, null, 0);
            options ~= o;
            if (tokens._error == "DocoptExit") {
                o = new Option(shortArg, null, 0, new ArgValue("true"));
            }
        } else {
            o = new Option(shortArg, similar[0]._longArg, similar[0]._argCount, similar[0]._value);
            string value = null;
            if (o._argCount != 0) {
                if (left == "") {
                    if (tokens.current == null || tokens.current == "--") {
                        writeln(format("%s requires an argument", shortArg));
                        assert(false);
                    }
                    value = tokens.move();
                } else {
                    value = left;
                    left = "";
                }
            }
            if (tokens._error == "DocoptExit") {
                if (value == null) {
                    o.setValue(new ArgValue("true"));
                } else {
                    o.setValue(new ArgValue(value));
                }
            }
        }
        parsed ~= o;
    }

    return parsed;
}

private Pattern parsePattern(string source, ref Option[] options) {
    auto tokens = new Tokens(source, "DocoptLanguageError");
    Pattern[] result = parseExpr(tokens, options);
    if (tokens.current() != null) {
        writeln("unexpected ending: %s", tokens.toString());
        assert(false);
    }
    return new Required(result);
}

private Pattern[] parseExpr(Tokens tokens, ref Option[] options) {
    Pattern[] seq = parseSeq(tokens, options);
    if (tokens.current() != "|") {
        return seq;
    }
    Pattern[] result;
    if (seq.length > 1) {
        result = [new Required(seq)];
    } else {
        result = seq;
    }
    while (tokens.current() == "|") {
        tokens.move();
        seq = parseSeq(tokens, options);
        if (seq.length > 1) {
            result ~= new Required(seq);
        } else {
            result ~= seq;
        }
    }

    if (result.length > 1) {
        return [new Either(result)];
    }

    return result;
}

private Pattern[] parseSeq(Tokens tokens, ref Option[] options) {
    Pattern[] result;
    while (!tokens.current().among("", "]", ")", "|")) {
        Pattern[] atom = parseAtom(tokens, options);
        if (tokens.current() == "...") {
            atom = [new OneOrMore(atom)];
            tokens.move();
        }
        result ~= atom;
    }
    return result;
}

private bool isUpperString(string s) {
    foreach (c; s) {
        if (!isUpper(c)) {
            return false;
        }
    }
    return true;
}

private Pattern[] parseAtom(Tokens tokens, ref Option[] options) {
    string token = tokens.current();
    Pattern[] result;
    string matching;
    Pattern pat;

    if (token == "(" || token == "[") {
        tokens.move();
        if (token == "(") {
            matching = ")";
            pat = new Required(parseExpr(tokens, options));
        } else {
            matching = "]";
            pat = new Optional(parseExpr(tokens, options));
        }
        if (tokens.move() != matching) {
            writeln("big fail");
            assert(false);
        }
        return [pat];
    } else if (token == "options") {
        tokens.move();
        return [new OptionsShortcut()];
    } else if (startsWith(token, "--") && token != "--") {
        return parseLong(tokens, options);
    } else if (startsWith(token, "-") && !token.among("-", "--")) {
        return parseShort(tokens, options);
    } else if ((startsWith(token, "<") && endsWith(token, ">")) || isUpperString(token)) {
        return [new Argument(tokens.move(), new ArgValue())];
    } else {
        return [new Command(tokens.move())];
    }
}

private Pattern[] parseArgv(Tokens tokens, ref Option[] options, bool optionsFirst) {
    Pattern[] parsed;

    while (tokens.current !is null) {
        if (tokens.current == "--") {
            foreach(tok; tokens._list) {
                parsed ~= new Argument(null, new ArgValue(tok));
            }
            return parsed;
        } else if (startsWith(tokens.current, "--")) {
            parsed ~= parseLong(tokens, options);
        } else if (startsWith(tokens.current, "-") && tokens.current != "-") {
            parsed ~= parseShort(tokens, options);
        } else if (optionsFirst) {
            foreach(tok; tokens._list) {
                parsed ~= new Argument(null, new ArgValue(tok));
            }
            return parsed;
        } else {
            parsed ~= new Argument(null, new ArgValue(tokens.move()));
        }
    }

    return parsed;
}

private Pattern[] subSetOptions(in Pattern[] docOptions, in Pattern[] patternOptions) {
    writeln("LeafPattern::match incomplete");
    assert(false);
}

private bool checkHelp(bool help, string vers, Pattern[] args, string doc) {
    if (help) {
        foreach(opt; args) {
            if ( (opt.name == "-h" || opt.name == "--help") && opt.value !is null) {
                writeln(doc);
                return true;
            }
        }
    }
    if (vers != null) {
        foreach(opt; args) {
            if ( opt.name == "--version" && opt.value !is null) {
                writeln(vers);
                return true;
            }
        }
    }
    return false;
}

public ArgValue[string] docopt(string doc, string[] argv,
                               bool help = false,
                               string vers = null,
                               bool optionsFirst = false) {
    ArgValue[string] dict;

    auto usageSections = parseSection("usage:", doc);
    if (usageSections.length == 0) {
        writeln("'usage:' (case-insensitive) not found.");
        return dict;
    }
    if (usageSections.length > 1) {
        writeln("More than one 'usage:' (case-insensitive)");
        return dict;
    }

    auto usageMsg = usageSections[0];

    writeln("---- usage --------");
    writeln(usageMsg);

    auto options = parseDefaults(doc);

    auto formal = formalUsage(usageMsg);

    auto pattern = parsePattern(formal, options);

    writeln("---- options --------");
    writeln(options);

    writeln("----- pattern -------");
    writeln(pattern);

    auto args = parseArgv(new Tokens(argv), options, optionsFirst);
    writeln("----  args  --------");
    writeln(new Tokens(argv));
    writeln(args);

    auto patternOptions = pattern.flat([typeid(Option).toString]);
    writeln("----  patternOptions  --------");
    writeln(patternOptions);

    foreach(ref shortcut; pattern.flat([typeid(OptionsShortcut).toString])) {
        auto docOptions = parseDefaults(doc);
        shortcut.setChildren(subSetOptions(docOptions, patternOptions));
    }

    if (checkHelp(help, vers, args, doc)) {
        writeln("checking help");
    } else {
        writeln("------ matching --------");
        PatternMatch match = pattern.fix().match(args);
        if (match.status && match.left.length == 0) {
            writeln("YAY");
            auto fin = pattern.flat() ~ match.collected;
            foreach(key; fin) {
                dict[key.name] = key.value;
            }
            writeln(dict);
        } else {
            writeln(match.status);
            writeln(match.left);
            writeln(match.collected);
            writeln("DANG");
        }
    }
    return dict;
}

unittest {

auto doc =
"   Usage:
        my_program tcp <host> <port> [--timeout=<seconds>]
        my_program serial <port> [--baud=<n>] [--timeout=<seconds>]
        my_program (-h | --help | --version)

    Options:
        -h, --help  Show this screen and exit.
        --baud=<n>  Baudrate [default: 9600]
";

/*
    string argv[5] = ["tcp", "127.0.0.1", "80", "--timeout", "30"];
    auto res = docopt(doc, argv, true, "0.1.0");
    writeln("---------------------------------------");
    docopt(doc, ["-h"], true, "0.1.0");

    writeln("---------------------------------------");
    docopt(doc, ["--version"], true, "0.1.0");
*/

auto doc2 =
"
    Usage: arguments [-vqrh] [FILE] ...
           arguments (--left | --right) CORRECTION FILE

    Process FILE and optionally apply correction to either left-hand side or
    right-hand side.

    Arguments:
        FILE        optional input file
        CORRECTION  correction angle, needs FILE, --left or --right to be present

    Options:
        -h --help
        -v       verbose mode
        -q       quiet mode
        -r       make report
        --left   use left-hand side
        --right  use right-hand side

";

    string argv2[3] = ["-r", "-v", "foo.txt"];
    auto res = docopt(doc2, argv2, true, "0.1.0");
}
