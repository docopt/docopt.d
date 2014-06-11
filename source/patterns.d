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

package struct PatternMatch {
    bool status;
    Pattern[] left;
    Pattern[] collected;
    this(bool s, in Pattern[] l, in Pattern[] c) {
        status = s;
        foreach(pat; l) {
            left ~= pat.dup;
        }
        foreach(pat; c) {
            collected ~= pat.dup;
        }
    }
    PatternMatch dup() {
        return PatternMatch(status, left, collected);
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

    const Pattern[] children() {
        return null;
    }

    const string name() {
        writeln("should never reach Pattern::name");
        return null;
    }

    const ArgValue value() {
        writeln("should never reach Pattern::value");
        return null;
    }

    void setName(in string name) {
        writeln("should never reach Pattern::setName");
    }

    void setValue(in ArgValue value) {
        writeln("should never reach Pattern::setValue");
    }

    void setChildren(in Pattern[] children) {
        writeln("should never reach Pattern::dup");
        assert(false);
    }

    const Pattern dup() {
        writeln("should never reach Pattern::dup");
        assert(false);
    }

    Pattern[] flat(string[] types = null) {
        writeln("should never reach Pattern::flat");
        assert(false);
    }

    PatternMatch match(Pattern[] left, Pattern[] collected = []) {
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
                either ~= temp.dup;
            }
        }
        writeln("------ either -------");
        writeln(either);
        writeln(either.length);
        foreach(item; either) {
            writeln("case ", item);
            foreach(i, child; item) {
                if (count(item, child) > 1) {
                    writeln(format("%d %s", i, child));
                    writeln("fixing repeater");
                    if (typeid(child) == typeid(Argument) || (typeid(child) == typeid(Option) && (cast(Option)child)._argCount==0)) {
                        writeln("we have a list?, what to do");
                        writeln(child);
                        assert(false);
                    }
                    if (typeid(child) == typeid(Command) || (typeid(child) == typeid(Option) && (cast(Option)child)._argCount==0)) {
                        child.setValue(new ArgValue("0"));
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
                writeln("one or more", child);
                groups ~= child.children ~ child.children ~ children;
                writeln(groups);
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
    writeln("-----------  transform ----------");
    Pattern res = new Either(required);
    writeln(res);
    return res;
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

    override const ArgValue value() {
        return _value.dup;
    }

    override void setName(in string name) {
        _name = name.dup;
    }

    override void setValue(in ArgValue value) {
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

    override PatternMatch match(Pattern[] left, Pattern[] collected = []) {
        ulong pos = ulong.max;
        auto match = singleMatch(left, pos);

        if (match is null) {
            return PatternMatch(false, left, collected);
        }
        assert(pos < ulong.max);

        Pattern[] left_;
        foreach(item; left[0..pos] ~ left[pos+1..$]) {
            left_ ~= item.dup;
        }

        Pattern[] sameName;
        foreach(item; collected) {
            if (item.name == name) {
                sameName ~= item.dup;
            }
        }

        if (_value.isInt || _value.isList) {
            if (_value.isInt) {
                if (sameName.length == 0) {
                    match.setValue(new ArgValue("1"));
                    return PatternMatch(true, left_, collected ~ match);
                } else {
                    ArgValue oldVal = match.value;
                    oldVal.add(1);
                    match.setValue(oldVal);
                }
            }

            // deal with lists
            if (_value.isList) {
                string [] increment;
                if (match.value.isString) {
                    increment = [match.value.toString];
                } else {
                    increment = match.value.value.dup;
                }
                if (sameName.length == 0) {
                    match.setValue(new ArgValue(increment));
                    return PatternMatch(true, left_, collected ~ match);
                } else {
                    ArgValue oldVal = match.value;
                    oldVal.add(increment);
                    match.setValue(oldVal);
                }
            }

            return PatternMatch(true, left_, collected);
        }

        auto c = collected ~ match;
        return PatternMatch(true, left_, c);
    }

    override const Pattern dup() {
        return new LeafPattern(_name, _value);
    }

    Pattern singleMatch(in Pattern[] left, ref ulong pos) {
        return null;
    }
}

package class Option : LeafPattern {
    string _shortArg;
    string _longArg;
    uint _argCount;
    ArgValue _value;
    this(in string s, in string l, in uint ac=0, in ArgValue v = new ArgValue("false") ) {
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

    override const ArgValue value() {
        return _value.dup;
    }

    override void setName(in string name) {
        _name = name.dup ;
    }

    override void setValue(in ArgValue value) {
        _value = value.dup;
    }

    override string toString() {
        return format("Option(%s, %s, %s, %s)", _shortArg, _longArg, _argCount, _value);
    }

    override const Option dup() {
        return new Option(_shortArg, _longArg, _argCount, _value);
    }

    override Pattern singleMatch(in Pattern[] left, ref ulong pos) {
        foreach (i, pat; left) {
            if (name == pat.name) {
                pos = i;
                return pat.dup;
            }
        }
        pos = ulong.max;
        return null;
    }
}

package class BranchPattern : Pattern {
    Pattern[] _children;

    protected this() {
    }

    this(in Pattern[] children) {
        foreach(child; children) {
            _children ~= child.dup;
        }
    }

    override Pattern[] children() {
        return _children;
    }

    override const Pattern[] children() {
        Pattern[] res;
        foreach(child; _children) {
            res ~= child.dup;
        }
        return res;
    }

    override void setChildren(in Pattern[] children) {
        _children.clear();
        foreach(child; children) {
            _children ~= child.dup;
        }
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

    override const Pattern dup() {
        return new BranchPattern(_children);
    }
}

private Pattern[] removeChild(Pattern[] arr, Pattern child) {
    Pattern[] result;
    foreach(pat; arr) {
        if(pat != child) {
            result ~= pat.dup;
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

    override Pattern singleMatch(in Pattern[] left, ref ulong pos) {
        foreach(i, pattern; left) {
            if (typeid(pattern) == typeid(Argument)) {
                pos = i;
                return new Argument(name, pattern.value);
            }
        }
        pos = ulong.max;
        return null;
    }
    override string toString() {
        string res;
        string temp = _value.toString;
        if (temp is null) {
            temp = "null";
        }
        return format("Argument(%s, %s)", _name, temp);
    }
    override const Pattern dup() {
        return new Argument(name, value);
    }
}

package class Command : Argument {
    this(string name, ArgValue value) {
        super(name, value);
    }
    this(string source) {
        super(source, new ArgValue("false"));
    }
    override Pattern singleMatch(in Pattern[] left, ref ulong pos) {
        foreach(i, pattern; left) {
            if (typeid(pattern) == typeid(Argument)) {
                if (pattern.value.toString == name) {
                    pos = i;
                    return new Command(name, new ArgValue("true"));
                } else {
                    break;
                }
            }
        }
        pos = ulong.max;
        return null;
    }
    override string toString() {
        return format("Command(%s, %s)", _name, _value);
    }
    override const Pattern dup() {
        return new Command(name, value);
    }
}

package class Required : BranchPattern {
    this(in Pattern[] children) {
        super(children);
    }

    override PatternMatch match(Pattern[] left, Pattern[] collected = []) {
        auto l = left;
        auto c = collected;
        foreach(child; _children) {
            PatternMatch res = child.match(l, c);
            if (!res.status) {
                return PatternMatch(false, left, collected);
            } else {
                l = res.left;
                c = res.collected;
            }
        }
        return PatternMatch(true, l, c);
    }

    override string toString() {
        string[] childNames;
        foreach(child; _children) {
            childNames ~= child.toString();
        }
        return format("Required(%s)", join(childNames, ", "));
    }

    override const Pattern dup() {
        return new Required(children);
    }
}

package class Optional : BranchPattern {
    this(in Pattern[] children) {
        super(children);
    }
    override PatternMatch match(Pattern[] left, Pattern[] collected = []) {
        PatternMatch res = PatternMatch(true, left, collected);
        foreach(child; _children) {
            res = child.match(left, collected);
        }
        return PatternMatch(true, res.left, res.collected);
    }
    override string toString() {
        string[] childNames;
        foreach(child; _children) {
            childNames ~= child.toString();
        }
        return format("Optional(%s)", join(childNames, ", "));
    }
    override const Pattern dup() {
        return new Optional(children);
    }
}

package class OptionsShortcut : Optional {
    this() {
        super([]);
    }
    this(in Pattern[] children) {
        super(children);
    }

    override string toString() {
        string[] childNames;
        foreach(child; _children) {
            childNames ~= child.toString();
        }
        return format("OptionsShortcut(%s)", join(childNames, ", "));
    }

    override const Pattern dup() {
        return new OptionsShortcut(children);
    }
}

package class OneOrMore : BranchPattern {
    this(in Pattern[] children) {
        super(children);
    }
    override PatternMatch match(Pattern[] left, Pattern[] collected = []) {
        assert(_children.length == 1);

        auto c = collected;

        Pattern[] l;
        foreach(item; left) {
            l ~= item.dup;
        }
        Pattern[] _l = null;

        bool matched = true;
        uint times = 0;
        while (matched) {
            auto match = _children[0].match(l, c);
            if (match.status) {
                times += 1;
            }
            if (_l == l) {
                break;
            }
            _l = match.left.dup;
        }
        if (times >= 1) {
            return PatternMatch(true, l, c);
        }
        return PatternMatch(false, left, collected);
    }
    override string toString() {
        string[] childNames;
        foreach(child; _children) {
            childNames ~= child.toString();
        }
        return format("OneOrMore(%s)", join(childNames, ", "));
    }
    override const Pattern dup() {
        return new OneOrMore(children);
    }
}

package class Either : BranchPattern {
    this(in Pattern[] children) {
        super(children);
    }

    override PatternMatch match(Pattern[] left, Pattern[] collected = []) {
        PatternMatch res = PatternMatch(false, left, collected);
        PatternMatch[] outcomes;
        foreach(child; _children) {
            auto outcome = child.match(left, collected);
            if (outcome.status) {
                outcomes ~= outcome;
            }
        }
        if (outcomes.length > 0) {
            auto minLeft = ulong.max;
            foreach (m; outcomes) {
                if (m.left.length < minLeft) {
                    minLeft = m.left.length;
                    res = m.dup;
                }
            }
        }
        return res;
    }
    override string toString() {
        string[] childNames;
        foreach(child; _children) {
            childNames ~= child.toString();
        }
        return format("Either(%s)", join(childNames, ", "));
    }
    override const Pattern dup() {
        return new Either(children);
    }
}

