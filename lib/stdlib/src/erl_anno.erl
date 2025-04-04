%%
%% %CopyrightBegin%
%%
%% SPDX-License-Identifier: Apache-2.0
%%
%% Copyright Ericsson AB 1996-2025. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% %CopyrightEnd%
%%

-module(erl_anno).
-moduledoc """
Abstract datatype for the annotations of the Erlang Compiler.

This module provides an abstract type that is used by the Erlang Compiler and
its helper modules for holding data such as column, line number, and text. The
data type is a collection of _annotations_{: #annotations } as described in the
following.

The Erlang Token Scanner returns tokens with a subset of the following
annotations, depending on the options:

- **`column`** - The column where the token begins.

- **`location`** - The line and column where the token begins, or just the line
  if the column is unknown.

- **`text`** - The token's text.

From this, the following annotation is derived:

- **`line`** - The line where the token begins.

This module also supports the following annotations, which are used by various
modules:

- **`file`** - A filename.

- **`generated`** - A Boolean indicating if the abstract code is
  compiler-generated. The Erlang Compiler does not emit warnings for such code.

- **`record`** - A Boolean indicating if the origin of the abstract code is a
  record. Used by [Dialyzer](`m:dialyzer`) to assign types to tuple elements.

The functions [`column()`](`erl_scan:column/1`),
[`end_location()`](`erl_scan:end_location/1`), [`line()`](`erl_scan:line/1`),
[`location()`](`erl_scan:location/1`), and [`text()`](`erl_scan:text/1`) in the
`erl_scan` module can be used for inspecting annotations in tokens.

The functions [`anno_from_term()`](`erl_parse:anno_from_term/1`),
[`anno_to_term()`](`erl_parse:anno_to_term/1`),
[`fold_anno()`](`erl_parse:fold_anno/3`),
[`map_anno()`](`erl_parse:map_anno/2`),
[`mapfold_anno()`](`erl_parse:mapfold_anno/3`), and
[`new_anno()`](`erl_parse:new_anno/1`), in the `erl_parse` module can be used
for manipulating annotations in abstract code.

## See Also

`m:erl_parse`, `m:erl_scan`
""".
-moduledoc(#{since => "OTP 18.0"}).

-export([new/1, is_anno/1]).
-export([column/1, end_location/1, file/1, generated/1,
         line/1, location/1, record/1, text/1]).
-export([set_file/2, set_generated/2, set_line/2, set_location/2,
         set_end_location/2, set_record/2, set_text/2]).

%% To be used when necessary to avoid Dialyzer warnings.
-export([to_term/1, from_term/1]).

-export_type([anno/0, line/0, column/0, location/0, text/0]).

-export_type([anno_term/0]).

-define(LN(L), is_integer(L), L >= 0).
-define(COL(C), (is_integer(C) andalso C >= 1)).

%% Location.
-define(LCOLUMN(C), ?COL(C)).
-define(LLINE(L), ?LN(L)).

%% Debug: define DEBUG to make sure that annotations are handled as an
%% opaque type. Note that all abstract code need to be compiled with
%% DEBUG=true. See also ./erl_pp.erl and ./erl_parse.yrl.

%-define(DEBUG, true).

-type annotation() :: {'file', filename()}
                    | {'generated', generated()}
                    | {'location', location()}
                    | {'end_location', location()}
                    | {'record', record()}
                    | {'text', string()}.

-ifdef(DEBUG).
-opaque anno() :: [annotation(), ...].
-else.
-doc "A collection of annotations.".
-opaque anno() :: location() | [annotation(), ...].
-endif.
-doc """
The term representing a collection of annotations. It is either a `t:location/0`
or a list of key-value pairs.
""".
-type anno_term() :: term().

-type column() :: pos_integer().
-type generated() :: boolean().
-type filename() :: file:filename_all().
-nominal line() :: non_neg_integer().
-nominal location() :: line() | {line(), column()}.
-type record() :: boolean().
-type text() :: string().

-ifdef(DEBUG).
%% Anything 'false' accepted by the compiler.
-define(ALINE(A), is_reference(A)).
-define(ACOLUMN(A), is_reference(A)).
-else.
-define(ALINE(L), ?LN(L)).
-define(ACOLUMN(C), ?COL(C)).
-endif.

-doc """
Returns the term representing the annotations Anno.

See also [from_term()](`from_term/1`).
""".
-doc(#{since => <<"OTP 18.0">>}).
-spec to_term(Anno) -> anno_term() when
      Anno :: anno().

-ifdef(DEBUG).
to_term(Anno) ->
    simplify(Anno).
-else.
to_term(Anno) ->
    Anno.
-endif.

-doc """
Returns annotations with representation Term.

See also [to_term()](`to_term/1`).
""".
-doc(#{since => <<"OTP 18.0">>}).
-spec from_term(Term) -> Anno when
      Term :: anno_term(),
      Anno :: anno().

-ifdef(DEBUG).
from_term(Term) when is_list(Term) ->
    Term;
from_term(Line) when is_integer(Line), Line < 0 -> % Before OTP 19
    set_generated(true, new(-Line));
from_term(Term) ->
    [{location, Term}].
-else.
from_term(Line) when is_integer(Line), Line < 0 -> % Before OTP 19
    set_generated(true, new(-Line));
from_term(Term) ->
    Term.
-endif.

-doc "Creates a new collection of annotations given a location.".
-doc(#{since => <<"OTP 18.0">>}).
-spec new(Location) -> anno() when
      Location :: location().

new(Line) when ?LLINE(Line) ->
    new_location(Line);
new({Line, Column}=Loc) when ?LLINE(Line), ?LCOLUMN(Column) ->
    new_location(Loc);
new(Term) ->
    erlang:error(badarg, [Term]).

-ifdef(DEBUG).
new_location(Location) ->
    [{location, Location}].
-else.
new_location(Location) ->
    Location.
-endif.

-doc "Returns `true` if Term is a collection of annotations, otherwise `false`.".
-doc(#{since => <<"OTP 18.0">>}).
-spec is_anno(Term) -> boolean() when
      Term :: any().

is_anno(Line) when ?ALINE(Line) ->
    true;
is_anno({Line, Column}) when ?ALINE(Line), ?ACOLUMN(Column) ->
    true;
is_anno(Anno) ->
    (Anno =/= [] andalso
     is_anno1(Anno) andalso
     lists:keymember(location, 1, Anno)).

is_anno1([{Item, Value}|Anno]) ->
    is_anno2(Item, Value) andalso is_anno1(Anno);
is_anno1(A) ->
    A =:= [].

is_anno2(location, Line) when ?LN(Line) ->
    true;
is_anno2(location, {Line, Column}) when ?LN(Line), ?COL(Column) ->
    true;
is_anno2(generated, true) ->
    true;
is_anno2(file, Filename) ->
    is_filename(Filename);
is_anno2(record, true) ->
    true;
is_anno2(text, Text) ->
    is_string(Text);
is_anno2(_, _) ->
    false.

is_filename(T) ->
    is_list(T) orelse is_binary(T).

is_string(T) ->
    is_list(T).

-doc "Returns the column of the annotations Anno.".
-doc(#{since => <<"OTP 18.0">>}).
-spec column(Anno) -> column() | 'undefined' when
      Anno :: anno().

column({Line, Column}) when ?ALINE(Line), ?ACOLUMN(Column) ->
    Column;
column(Line) when ?ALINE(Line) ->
    undefined;
column(Anno) ->
    case location(Anno) of
        {_Line, Column} ->
            Column;
        _Line ->
            undefined
    end.

-doc """
Returns the end location of the annotations Anno.

If the end location annotation is present, its value is returned. Otherwise,
if the text annotation is present, the end location is inferred from the
location and the text. Finally, if there is no text, `undefined` is returned.
""".
-doc(#{since => <<"OTP 18.0">>}).
-spec end_location(Anno) -> location() | 'undefined' when
      Anno :: anno().

end_location(Line) when ?ALINE(Line) ->
    undefined;
end_location({Line, Column}) when ?ALINE(Line), ?ACOLUMN(Column) ->
    undefined;
end_location(Anno) ->
    case anno_info(Anno, end_location) of
        undefined ->
            case text(Anno) of
                undefined ->
                    undefined;
                Text ->
                    case location(Anno) of
                        {Line, Column} ->
                            end_location(Text, Line, Column);
                        Line ->
                            end_location(Text, Line)
                    end
            end;

        Location ->
            Location
    end.

-doc """
Returns the filename of the annotations Anno. If there is no filename,
`undefined` is returned.
""".
-doc(#{since => <<"OTP 18.0">>}).
-spec file(Anno) -> filename() | 'undefined' when
      Anno :: anno().

file(Line) when ?ALINE(Line) ->
    undefined;
file({Line, Column}) when ?ALINE(Line), ?ACOLUMN(Column) ->
    undefined;
file(Anno) ->
    anno_info(Anno, file).

-doc """
Returns `true` if annotations Anno is marked as generated. The default is to
return `false`.
""".
-doc(#{since => <<"OTP 18.0">>}).
-spec generated(Anno) -> generated() when
      Anno :: anno().

generated(Line) when ?ALINE(Line) ->
    false;
generated({Line, Column}) when ?ALINE(Line), ?ACOLUMN(Column) ->
    false;
generated(Anno) ->
    anno_info(Anno, generated, false).

-doc "Returns the line of the annotations Anno.".
-doc(#{since => <<"OTP 18.0">>}).
-spec line(Anno) -> line() when
      Anno :: anno().

line(Anno) ->
    case location(Anno) of
        {Line, _Column} ->
            Line;
        Line ->
            Line
    end.

-doc """
Returns the location of the annotations Anno. If there is no location,
a zero line number is returned.
""".
-doc(#{since => <<"OTP 18.0">>}).
-spec location(Anno) -> location() when
      Anno :: anno().

location(Line) when ?ALINE(Line) ->
    Line;
location({Line, Column}=Location) when ?ALINE(Line), ?ACOLUMN(Column) ->
    Location;
location(Anno) ->
    anno_info(Anno, location, 0).

-doc false.
-spec record(Anno) -> record() when
      Anno :: anno().

record(Line) when ?ALINE(Line) ->
    false;
record({Line, Column}) when ?ALINE(Line), ?ACOLUMN(Column) ->
    false;
record(Anno) ->
    anno_info(Anno, record, false).

-doc """
Returns the text of the annotations Anno. If there is no text, `undefined` is
returned.
""".
-doc(#{since => <<"OTP 18.0">>}).
-spec text(Anno) -> text() | 'undefined' when
      Anno :: anno().

text(Line) when ?ALINE(Line) ->
    undefined;
text({Line, Column}) when ?ALINE(Line), ?ACOLUMN(Column) ->
    undefined;
text(Anno) ->
    anno_info(Anno, text).

-doc "Modifies the filename of the annotations Anno.".
-doc(#{since => <<"OTP 18.0">>}).
-spec set_file(File, Anno) -> Anno when
      File :: filename(),
      Anno :: anno().

set_file(File, Anno) ->
    set(file, File, Anno).

-doc "Modifies the generated marker of the annotations Anno.".
-doc(#{since => <<"OTP 18.0">>}).
-spec set_generated(Generated, Anno) -> Anno when
      Generated :: generated(),
      Anno :: anno().

set_generated(Generated, Anno) ->
    set(generated, Generated, Anno).

-doc "Modifies the line of the annotations Anno.".
-doc(#{since => <<"OTP 18.0">>}).
-spec set_line(Line, Anno) -> Anno when
      Line :: line(),
      Anno :: anno().

set_line(Line, Anno) ->
    case location(Anno) of
        {_Line, Column} ->
            set_location({Line, Column}, Anno);
        _Line ->
            set_location(Line, Anno)
    end.

-doc "Modifies the location of the annotations Anno.".
-doc(#{since => <<"OTP 18.0">>}).
-spec set_location(Location, Anno) -> Anno when
      Location :: location(),
      Anno :: anno().

set_location(Line, L) when ?ALINE(L), ?LLINE(Line) ->
    new_location(Line);
set_location(Line, {L, Column}) when ?ALINE(L), ?ACOLUMN(Column),
                                     ?LLINE(Line) ->
    new_location(Line);
set_location({L, C}=Loc, Line) when ?ALINE(Line), ?LLINE(L), ?LCOLUMN(C) ->
    new_location(Loc);
set_location({L, C}=Loc, {Line, Column}) when ?ALINE(Line), ?ACOLUMN(Column),
                                              ?LLINE(L), ?LCOLUMN(C) ->
    new_location(Loc);
set_location(Location, Anno) ->
    set(location, Location, Anno).

-doc "Modifies the end location of the annotations Anno.".
-doc(#{since => <<"OTP 28.0">>}).
-spec set_end_location(Location, Anno) -> Anno when
      Location :: location(),
      Anno :: anno().

set_end_location(Location, Anno) ->
    set(end_location, Location, Anno).

-doc "Modifies the record marker of the annotations Anno.".
-doc(#{since => <<"OTP 18.0">>}).
-spec set_record(Record, Anno) -> Anno when
      Record :: record(),
      Anno :: anno().

set_record(Record, Anno) ->
    set(record, Record, Anno).

-doc "Modifies the text of the annotations Anno.".
-doc(#{since => <<"OTP 18.0">>}).
-spec set_text(Text, Anno) -> Anno when
      Text :: text(),
      Anno :: anno().

set_text(Text, Anno) ->
    set(text, Text, Anno).

set(Item, Value, Anno) ->
    case {is_settable(Item, Value), Anno} of
        {true, Line} when ?ALINE(Line) ->
            set_anno(Item, Value, [{location, Line}]);
        {true, {L, C}=Location} when ?ALINE(L), ?ACOLUMN(C) ->
            set_anno(Item, Value, [{location, Location}]);
        {true, A} when is_list(A), A =/= [] ->
            set_anno(Item, Value, Anno);
        _ ->
            erlang:error(badarg, [Item, Value, Anno])
    end.

set_anno(Item, Value, Anno) ->
    case default(Item, Value) of
        true ->
            reset(Anno, Item);
        false ->
            R = case anno_info(Anno, Item) of
                    undefined ->
                        [{Item, Value}|Anno];
                    _ ->
                        lists:keyreplace(Item, 1, Anno, {Item, Value})
                end,
            reset_simplify(R)
    end.

reset(Anno, Item) ->
    A = lists:keydelete(Item, 1, Anno),
    reset_simplify(A).

-ifdef(DEBUG).
reset_simplify(A) ->
    A.
-else.
reset_simplify(A) ->
    simplify(A).
-endif.

simplify([{location, Location}]) ->
    Location;
simplify(Anno) ->
    Anno.

anno_info(Anno, Item, Default) ->
    try lists:keyfind(Item, 1, Anno) of
        false ->
            Default;
        {Item, Value} ->
            Value
    catch
        _:_ ->
            erlang:error(badarg, [Anno, Item, Default])
    end.

anno_info(Anno, Item) ->
    try lists:keyfind(Item, 1, Anno) of
        {Item, Value} ->
            Value;
        false ->
            undefined
    catch
        _:_ ->
            erlang:error(badarg, [Anno, Item])
    end.

end_location("", Line, Column) ->
    {Line, Column};
end_location([$\n|String], Line, _Column) ->
    end_location(String, Line+1, 1);
end_location([_|String], Line, Column) ->
    end_location(String, Line, Column+1).

end_location("", Line) ->
    Line;
end_location([$\n|String], Line) ->
    end_location(String, Line+1);
end_location([_|String], Line) ->
    end_location(String, Line).

is_settable(file, File) ->
    is_filename(File);
is_settable(generated, Boolean) when Boolean; not Boolean ->
    true;
is_settable(location, Line) when ?LLINE(Line) ->
    true;
is_settable(location, {Line, Column}) when ?LLINE(Line), ?LCOLUMN(Column) ->
    true;
is_settable(end_location, Line) when ?LLINE(Line) ->
    true;
is_settable(end_location, {Line, Column}) when ?LLINE(Line), ?LCOLUMN(Column) ->
    true;
is_settable(record, Boolean) when Boolean; not Boolean ->
    true;
is_settable(text, Text) ->
    is_string(Text);
is_settable(_, _) ->
    false.

default(generated, false) -> true;
default(record, false) -> true;
default(_, _) -> false.
