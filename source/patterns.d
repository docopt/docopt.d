import std.stdio;
import std.regex;
import std.string;
import std.array;
import std.algorithm;
import std.container;
import std.traits;
import std.ascii;
import std.conv;
import std.c.stdlib;

import argvalue;

package struct PatternMatch {
    bool status;
    Pattern[] left;
    Pattern[] collected;
    this(bool s, Pattern[] l, Pattern[] c) {
        status = s;
        foreach(pat; l) {
            left ~= pat;
        }
        foreach(pat; c) {
            collected ~= pat;
        }
    }
}

package abstract class Pattern {
    override bool opEquals(Object rhs) {
       return (this.toString() == rhs.toString());
    }

    override size_t toHash() {
        return typeid(this).getHash(&this);
    }

    override string toString() {
        return "Pattern";
    }

    Pattern[] children() {
        return null;
    }

    const string name() {
        writeln("should never reach Pattern::name");
        return null;
    }

    ArgValue value() {
        writeln("should never reach Pattern::value");
        return null;
    }

    void setName(string name) {
        writeln("should never reach Pattern::setName");
    }

    void setValue(ArgValue value) {
        writeln("should never reach Pattern::setValue");
    }

    void setChildren(Pattern[] children) {
        writeln("should never reach Pattern::dup");
        assert(false);
    }

    Pattern[] flat(string[] types = null) {
        writeln("should never reach Pattern::flat");
        assert(false);
    }

    bool match(ref Pattern[] left, ref Pattern[] collected) {
        writeln("should never reach Pattern::match");
        assert(false);
    }

    Pattern fix() {
        fixIdentities();
        fixRepeatingArguments();
        return this;
    }

    // make pattern-tree tips point to same object if they are equal
    Pattern fixIdentities(Pattern[] uniq = []) {
        if (uniq.length == 0) {
            foreach(pattern; flat()) {
                if (find(uniq, pattern) == []) {
                    uniq ~= pattern;
                }
            }
        }
        foreach(i, ref child; children()) {
            if (child.children is null) {
                auto place = find(uniq, child);
                assert(place != []);
                child = place[0];
            } else {
                child.fixIdentities(uniq);
            }
        }
        return this;
    }

    Pattern fixRepeatingArguments() {
        Pattern[][] either;
        foreach(i, child; transform(this).children()) {
            if (child.children !is null) {
                Pattern[] temp;
                foreach(c; child.children) {
                    temp ~= c;
                }
                either ~= temp;
            }
        }
        foreach(item; either) {
            foreach(i, child; item) {
                if (count(item, child) > 1) {
                    if (typeid(child) == typeid(Argument) || (typeid(child) == typeid(Option) && (cast(Option)child)._argCount==0)) {
                        if (child.value.isNull) {
                            string[] temp;
                            child.setValue(new ArgValue(temp));
                        } else if (child.value.isString) {
                            writeln("need to split string into list");
                            assert(false);
                        }
                    }
                    if (typeid(child) == typeid(Command) || (typeid(child) == typeid(Option) && (cast(Option)child)._argCount==0)) {
                        child.setValue(new ArgValue(0));
                    }
                }
            }
        }
        return this;
    }
}

private Pattern transform(Pattern pattern) {
    Pattern[][] result;
    Pattern[][] groups = [[pattern]];

    TypeInfo[] parents = [typeid(Required), typeid(Optional),
                          typeid(OptionsShortcut), typeid(Either),
                          typeid(OneOrMore)];

    while (groups.length > 0) {
        Pattern[] children = groups[0];
        groups = groups[1..$];

        bool any = false;
        foreach(c; children) {
            if (find(parents, typeid(c)) != []) {
                any = true;
            }
        }

        if (any) {
            Pattern[] currentChildren;
            foreach(c; children) {
                if (find(parents, typeid(c)) != []) {
                    currentChildren ~= c;
                }
            }
            assert(currentChildren.length > 0);

            Pattern child = currentChildren[0];
            children = removeChild(children, child);
            if (typeid(child) == typeid(Either)) {
                foreach(e; child.children) {
                    groups ~= [e] ~ children;
                }
            }
            else if (typeid(child) == typeid(OneOrMore)) {
                groups ~= child.children ~ child.children ~ children;
            }
            else {
                groups ~= child.children ~ children;
            }
        } else {
            result ~= children;
        }
    }
    Pattern[] required;
    foreach(e; result) {
        required ~= new Required(e);
    }
    return new Either(required);
}


package class LeafPattern : Pattern {
    protected string _name = null;
    protected ArgValue _value = null;

    this(in string name, in ArgValue value = null) {
        _name = name.dup;
        if (value !is null) {
            _value = value.dup;
        }
    }

    override const string name() {
        return _name;
    }

    override ArgValue value() {
        return _value;
    }

    override void setName(string name) {
        _name = name;
    }

    override void setValue(ArgValue value) {
        if (value !is null) {
            _value = value.dup;
        } else {
            _value = null;
        }
    }

    override string toString() {
        return format("%s(%s, %s)", "LeafPattern", _name, _value.toString);
    }

    override Pattern[] flat(string[] types = null) {
        if (types is null || canFind(types, typeid(this).toString)) {
            return [this];
        }
        return [];
    }

    override bool match(ref Pattern[] left, ref Pattern[] collected) {
        uint pos = uint.max;
        auto match = singleMatch(left, pos);

        if (match is null) {
            return false;
        }
        assert(pos < uint.max);

        Pattern[] left_ = left[0..pos] ~ left[pos+1..$];

        Pattern[] sameName;
        foreach(item; collected) {
            if (item.name == name) {
                sameName ~= item;
            }
        }

        if (_value.isInt || _value.isList) {
            if (_value.isInt) {
                if (sameName.length == 0) {
                    match.setValue(new ArgValue(1));
                    collected ~= match;
                    left = left;
                    return true;
                } else {
                    ArgValue oldVal = match.value;
                    oldVal.add(1);
                    sameName[0].setValue(oldVal);
                }
            }

            // deal with lists
            if (_value.isList) {
                string [] increment;
                if (match.value.isString) {
                    increment = [match.value.toString];
                } else {
                    increment = match.value.asList;
                }
                if (sameName.length == 0) {
                    match.setValue(new ArgValue(increment));
                    collected ~= match;
                    left = left_;
                    return true;
                } else {
                    ArgValue oldVal = match.value;
                    oldVal.add(increment);
                    sameName[0].setValue(oldVal);
                }
            }

            left = left_;
            return true;
        }

        collected ~= match;
        left = left_;
        return true;
    }

    Pattern singleMatch(Pattern[] left, ref uint pos) {
        return null;
    }
}

package class Option : LeafPattern {
    string _shortArg;
    string _longArg;
    uint _argCount;
    ArgValue _value;
    this(in string s, in string l, in uint ac=0, in ArgValue v = new ArgValue(false) ) {
        if (l != null) {
            super(l, v);
        } else {
            super(s, v);
        }
        _shortArg = s.dup;
        _longArg = l.dup;
        _argCount = ac;
        _value = v.dup;
    }

    override const string name() {
        if (_longArg != null) {
            return _longArg;
        } else {
            return _shortArg;
        }
    }

    override ArgValue value() {
        return _value;
    }

    override void setName(string name) {
        _name = name;
    }

    override void setValue(ArgValue value) {
        _value = value;
    }

    override string toString() {
        string s = "None";
        if (_shortArg != null) {
            s = format("'%s'", _shortArg);
        }
        string l = "None";
        if (_longArg != null) {
            l = format("'%s'", _longArg);
        }

        return format("Option(%s, %s, %s, %s)", s, l, _argCount, _value);
    }

    override Pattern singleMatch(Pattern[] left, ref uint pos) {
        foreach (uint i, pat; left) {
            if (name == pat.name) {
                pos = i;
                return pat;
            }
        }
        pos = uint.max;
        return null;
    }
}

package class BranchPattern : Pattern {
    Pattern[] _children;

    protected this() {
    }

    this(Pattern[] children) {
        _children = children;
    }

    override Pattern[] children() {
        return _children;
    }

    override void setChildren(Pattern[] children) {
        _children = children;
    }

    override string toString() {
        string[] childNames;
        foreach(child; _children) {
            childNames ~= child.toString();
        }
        return format("BranchPattern(%s)", join(childNames, ", "));
    }

    override Pattern[] flat(string[] types = null) {
        if (canFind(types, typeid(this).toString)) {
            return [this];
        }
        Pattern[] res;
        foreach(child; _children) {
            res ~= child.flat(types);
        }
        return res;
    }

    //override const Pattern dup() {
    //    return new BranchPattern(_children);
    //}
}

// TODO remove first match
private Pattern[] removeChild(Pattern[] arr, Pattern child) {
    Pattern[] result;
    bool found = false;
    foreach(pat; arr) {
        if(found || pat != child) {
            result ~= pat;
        }
        if (pat == child) {
            found = true;
        }
    }
    return result;
}

package class Argument : LeafPattern {
    this(string name, ArgValue value) {
        super(name, value);
    }

    this(string source) {
        auto namePat = regex(r"(<\S*?>)");
        auto match = matchAll(source, namePat);
        string name = "";
        if (!match.empty()) {
            name = match.captures[0];
        }
        auto valuePat = regex(r"\[default: (.*)\]", "i");
        match = matchAll(source, valuePat);
        string value = "";
        if (!match.empty()) {
            value = match.captures[0];
        }
        super(name, new ArgValue(value));
    }

    override Pattern singleMatch(Pattern[] left, ref uint pos) {
        foreach(i, pattern; left) {
            if (typeid(pattern) == typeid(Argument)) {
                pos = i;
                return new Argument(name, pattern.value);
            }
        }
        pos = uint.max;
        return null;
    }

    override string toString() {
        string temp = _value.toString;
        if (temp is null) {
            temp = "None";
        }
        string n = format("'%s'", _name);
        return format("Argument(%s, %s)", n, temp);
    }
}

package class Command : Argument {
    this(string name, ArgValue value) {
        super(name, value);
    }
    this(string source) {
        super(source, new ArgValue(false));
    }
    override Pattern singleMatch(Pattern[] left, ref uint pos) {
        foreach(i, pattern; left) {
            if (typeid(pattern) == typeid(Argument)) {
                if (pattern.value.toString == name) {
                    pos = i;
                    return new Command(name, new ArgValue(true));
                } else {
                    break;
                }
            }
        }
        pos = uint.max;
        return null;
    }
    override string toString() {
        return format("Command(%s, %s)", _name, _value);
    }
}

package class Required : BranchPattern {
    this(Pattern[] children) {
        super(children);
    }

    override bool match(ref Pattern[] left, ref Pattern[] collected) {
        auto l = left;
        auto c = collected;
        foreach(child; _children) {
            auto res = child.match(l, c);
            if (!res) {
                return false;
            }
        }
        left = l;
        collected = c;
        return true;
    }

    override string toString() {
        string[] childNames;
        foreach(child; _children) {
            childNames ~= child.toString();
        }
        return format("Required(%s)", join(childNames, ", "));
    }
}

package class Optional : BranchPattern {
    this(Pattern[] children) {
        super(children);
    }
    override bool match(ref Pattern[] left, ref Pattern[] collected) {
        foreach(child; _children) {
            auto res = child.match(left, collected);
        }
        return true;
    }
    override string toString() {
        string[] childNames;
        foreach(child; _children) {
            childNames ~= child.toString();
        }
        return format("Optional(%s)", join(childNames, ", "));
    }
}

package class OptionsShortcut : Optional {
    this() {
        super([]);
    }
    this(Pattern[] children) {
        super(children);
    }

    override string toString() {
        string[] childNames;
        foreach(child; _children) {
            childNames ~= child.toString();
        }
        return format("OptionsShortcut(%s)", join(childNames, ", "));
    }
}

package class OneOrMore : BranchPattern {
    this(Pattern[] children) {
        super(children);
    }
    override bool match(ref Pattern[] left, ref Pattern[] collected) {
        assert(_children.length == 1);

        auto c = collected;
        Pattern[] l = left;
        Pattern[] _l = null;

        bool matched = true;
        uint times = 0;
        while (matched) {
            auto match = _children[0].match(l, c);
            if (match) {
                times += 1;
            } else {
                times = 0;
            }
            if (_l == l) {
                break;
            }
            _l = l;
        }
        if (times >= 1) {
            left = l;
            collected = c;
            return true;
        }
        return false;
    }

    override string toString() {
        string[] childNames;
        foreach(child; _children) {
            childNames ~= child.toString();
        }
        return format("OneOrMore(%s)", join(childNames, ", "));
    }
}

package class Either : BranchPattern {
    this(Pattern[] children) {
        super(children);
    }

    override bool match(ref Pattern[] left, ref Pattern[] collected) {
        PatternMatch res = PatternMatch(false, left, collected);
        PatternMatch[] outcomes;
        foreach(child; _children) {
            auto l = left;
            auto c = collected;
            auto matched = child.match(l, c);
            if (matched) {
                outcomes ~= PatternMatch(matched, l, c);
            }
        }
        if (outcomes.length > 0) {
            auto minLeft = uint.max;
            foreach (m; outcomes) {
                if (m.left.length < minLeft) {
                    minLeft = m.left.length;
                    res = m;
                }
            }
        }
        collected = res.collected;
        left = res.left;
        return true;
    }
    override string toString() {
        string[] childNames;
        foreach(child; _children) {
            childNames ~= child.toString();
        }
        return format("Either(%s)", join(childNames, ", "));
    }
}

