import std.string;
import std.regex;
import std.array;

package class Tokens {
    string[] _list;
    string _error;
    this(string[] source, string err="DocoptExit") {
        _list ~= source;
        _error = err;
    }
    this(string source, string err="DocoptError") {
        auto pat = regex(r"([\[\]\(\)\|]|\.\.\.)");
        string newSource = replaceAll(source, pat, r" $1 ");
        auto splitPat = regex(r"\s+|(\S*<.*?>)");
        auto parts = split(newSource, splitPat);
        auto match = array(matchAll(newSource, splitPat));
        auto l = parts.length;
        for(auto i = 0; i < l; i++) {
            if (parts[i].length > 0) {
                _list ~= parts[i];
            }
            if (i < l-1 && match[i][1].length > 0) {
                _list ~= match[i][1];
            }
        }
        _error = err;
    }
    string move() {
        if (_list.length > 0) {
            string res = _list[0].dup;
            _list = _list[1..$];
            return res;
        } else {
            return null;
        }
    }
    string current() {
        if (_list.length > 0) {
            return _list[0].dup;
        } else {
            return null;
        }
    }

    // TODO remove these eventually
    override string toString() {
        string result = "[";
        result ~= join(_list, ", ");
        return result ~= "]";
    }
    size_t length() {
        return _list.length;
    }
}

