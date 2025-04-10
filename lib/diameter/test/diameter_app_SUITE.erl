%%
%% %CopyrightBegin%
%%
%% SPDX-License-Identifier: Apache-2.0
%%
%% Copyright Ericsson AB 2010-2025. All Rights Reserved.
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

%%
%% Tests based on the contents of the diameter app file.
%%

-module(diameter_app_SUITE).

%% testcases, no common_test dependency
-export([run/0,
         run/1]).

%% common_test wrapping
-export([
         %% Framework functions
         suite/0,
         all/0,
         init_per_suite/1,
         end_per_suite/1,
         init_per_testcase/2,
         end_per_testcase/2
        ]).

%% testcases
-export([keys/1,
         vsn/1,
         modules/1,
         exports/1,
         release/1,
         xref/1,
         relup/1]).

-include_lib("kernel/include/file.hrl").

-include("diameter_util.hrl").


%% ===========================================================================

-define(A, list_to_atom).

%% Modules not in the app and that should not have dependencies on it
%% for build reasons.
-define(COMPILER_MODULES, [diameter_codegen,
                           diameter_dict_scanner,
                           diameter_dict_parser,
                           diameter_dict_util,
                           diameter_exprecs,
                           diameter_make]).

-define(INFO_MODULES, [diameter_dbg,
                       diameter_info]).

-define(AL(F),    ?AL(F, [])).
-define(AL(F, A), ?LOG("DAPPS", F, A)).


%% ===========================================================================

suite() ->
    [{timetrap, {seconds, 120}}].

all() ->
    [keys,
     vsn,
     modules,
     exports,
     release,
     xref,
     relup].


init_per_suite(Config) ->
    ?DUTIL:init_per_suite(Config).


end_per_suite(Config) ->
    ?DUTIL:end_per_suite(Config).


%% This test case can take a *long* time, so if the machine is too slow, skip
init_per_testcase(xref = Case, Config) when is_list(Config) ->
    ?AL("init_per_testcase(~w) -> check factor", [Case]),
    Key = dia_factor,
    case lists:keysearch(Key, 1, Config) of
        {value, {Key, Factor}} when (Factor > 10) ->
            ?AL("init_per_testcase(~w) -> Too slow (~w) => SKIP",
                [Case, Factor]),
            {skip, {machine_too_slow, Factor}};
        _ ->
            ?AL("init_per_testcase(~w) -> run test", [Case]),
            Config
    end;
init_per_testcase(Case, Config) ->
    ?AL("init_per_testcase(~w) -> entry", [Case]),
    Config.


end_per_testcase(Case, Config) when is_list(Config) ->
    ?AL("end_per_testcase(~w) -> entry", [Case]),
    Config.


%% ===========================================================================

run() ->
    run(all()).

run(List) ->
    Tmp = ?MKTEMP("diameter_app"),
    try
        run([{priv_dir, Tmp}], List)
    after
        file:del_dir_r(Tmp)
    end.

run(Config, List) ->
    Timeout = factor2timeout(Config, 10000),
    ?AL("run -> use Timeout: ~w", [Timeout]),
    [{application, diameter, App}] = ?CONSULT(diameter, app),
    ?RUN([{{?MODULE, F, [{App, Config}]}, Timeout} || F <- List]).


factor2timeout(Config, BaseTime) ->
    Key = dia_factor,
    case lists:keysearch(Key, 1, Config) of
        {value, {Key, Factor}} when (Factor > 0) ->
            BaseTime + (((Factor-1)*BaseTime) div 10);
        _ ->
            BaseTime
    end.

    
%% ===========================================================================
%% # keys/1
%%
%% Ensure that the app file contains selected keys. Some of these would
%% also be caught by other testcases.
%% ===========================================================================

keys({App, _Config}) ->
    [] = lists:filter(fun(K) -> not lists:keymember(K, 1, App) end,
                      [vsn, description, modules, registered, applications]);

keys(Config) ->
    run(Config, [keys]).

%% ===========================================================================
%% # vsn/1
%%
%% Ensure that our app version sticks to convention.
%% ===========================================================================

vsn({App, _Config}) ->
    true = is_vsn(fetch(vsn, App));

vsn(Config) ->
    run(Config, [vsn]).

%% ===========================================================================
%% # modules/1
%%
%% Ensure that the app file modules and installed modules differ by
%% compiler/info modules.
%% ===========================================================================

modules({App, _Config}) ->
    Mods = fetch(modules, App),
    Installed = code_mods(),
    Help = lists:sort(?INFO_MODULES ++ ?COMPILER_MODULES),
    {[], Help} = {Mods -- Installed, lists:sort(Installed -- Mods)};

modules(Config) ->
    run(Config, [modules]).

code_mods() ->
    Dir  = ?LIB_DIR(diameter, ebin),
    {ok, Files} = file:list_dir(Dir),
    [?A(lists:reverse(R)) || N <- Files, "maeb." ++ R <- [lists:reverse(N)]].


%% ===========================================================================
%% # exports/1
%%
%% Ensure that no module does export_all.
%% ===========================================================================

exports({App, _Config}) ->
    Mods = fetch(modules, App),
    [] = [M || M <- Mods, exports_all(M)];

exports(Config) ->
    run(Config, [exports]).

exports_all(Mod) ->
    Opts = fetch(options, Mod:module_info(compile)),

    is_list(Opts) andalso lists:member(export_all, Opts).

%% ===========================================================================
%% # release/1
%%
%% Ensure that it's possible to build a minimal release with our app file.
%% ===========================================================================

release({App, Config}) ->
    Rel = {release,
           {"diameter test release", fetch(vsn, App)},
           {erts, erlang:system_info(version)},
           [{A, appvsn(A)} || A <- [sasl | fetch(applications, App)]]},
    Dir = fetch(priv_dir, Config),
    ok = write_file(filename:join([Dir, "diameter_test.rel"]), Rel),
    {ok, _, []} = systools:make_script("diameter_test", [{path, [Dir]},
                                                         {outdir, Dir},
                                                         silent]);

release(Config) ->
    run(Config, [release]).

%% sasl need to be included to avoid a missing_sasl warning, error
%% in the case of relup/1.

appvsn(Name) ->
    [{application, Name, App}] = ?CONSULT(Name, app),
    fetch(vsn, App).

%% ===========================================================================
%% # xref/1
%%
%% Ensure that no function in our application calls an undefined function
%% or one in an application we haven't declared as a dependency. (Almost.)
%% ===========================================================================

xref({App, _Config}) ->
    ?AL("xref -> entry with"
        "~n   App:    ~p"
        "~n   Config: ~p", [App, _Config]),

    Mods = fetch(modules, App),  %% modules listed in the app file

    %% List of application names extracted from runtime_dependencies.
    ?AL("xref -> get deps"),
    Deps = lists:map(fun unversion/1, fetch(runtime_dependencies, App)),

    ?AL("xref -> start xref"),
    {ok, XRef} = xref:start(make_name(xref_test_name)),
    ok = xref:set_default(XRef, [{verbose, false}, {warnings, false}]),

    %% Only add our application and those it's dependent on according
    %% to the app file. Well, almost. erts beams are also required to
    %% stop xref from complaining about calls to module erlang, which
    %% was previously in kernel. Erts isn't an application however, in
    %% the sense that there's no .app file, and isn't listed in
    %% applications.
    Apps = [diameter, erts | fetch(applications, App)],
    ?AL("xref -> add own and dep apps: "
        "~n   ~p", [Apps]),
    ok = lists:foreach(fun(A) -> add_application(XRef, A) end, Apps),

    ?AL("xref -> analyze undefined_function_calls"),
    {ok, Undefs} = xref:analyze(XRef, undefined_function_calls),
    ?AL("xref -> analyze module use: "
        "~n   For mods: ~p", [Mods]),
    {ok, RTmods} = xref:analyze(XRef, {module_use, Mods}),
    ?AL("xref -> analyze (compiler) module use: "
        "~n   For mods: ~p", [?COMPILER_MODULES]),
    {ok, CTmods} = xref:analyze(XRef, {module_use, ?COMPILER_MODULES}),
    ?AL("xref -> analyze module call: "
        "~n   For mods: ~p", [Mods]),
    {ok, RTdeps} = xref:analyze(XRef, {module_call, Mods}),

    ?AL("xref -> stop xref"),
    xref:stop(XRef),

    ?AL("xref -> get OTP release"),
    Rel = release(),  %% otp_release-ish

    %% Only care about calls from our own application.
    ?AL("xref -> Only care about calls from our own application"),
    [] = lists:filter(fun({{F,_,_} = From, {_,_,_} = To}) ->
                              lists:member(F, Mods)
                                  andalso not ignored(From, To, Rel)
                      end,
                      Undefs),

    %% Ensure that only runtime or info modules call runtime modules.
    %% It's not strictly necessary that diameter compiler modules not
    %% depend on other diameter modules but it's a simple source of
    %% build errors if not properly encoded in the makefile so guard
    %% against it.
    ?AL("xref -> ensure only runtime and info mod"),
    [] = (RTmods -- Mods) -- ?INFO_MODULES,

    %% Ensure that runtime modules don't call compiler modules.
    ?AL("xref -> ensure runtime mods don't call compiler mods"),
    CTmods = CTmods -- Mods,

    %% Ensure that runtime modules only call other runtime modules, or
    %% applications declared in runtime_dependencies in the app file.
    %% The declared application versions are ignored since we only
    %% know what we see now.
    ?AL("xref -> ensure runtime mods only call runtime mods"),
    [] = lists:filter(fun(M) -> not lists:member(app(M), Deps) end,
                      RTdeps -- Mods),

    ?AL("xref -> done"),
    ok;

xref(Config) ->
    ?AL("xref -> entry with"
        "~n   Config: ~p", [Config]),
    Res = run(Config, [xref]),
    ?AL("xref -> done when"
        "~n   Res: ~p", [Res]),
    Res.

ignored({FromMod,_,_}, {ToMod,_,_} = To, Rel)->
    %% diameter_tcp does call ssl despite the latter not being listed
    %% as a dependency in the app file since ssl is only required for
    %% TLS security: it's up to a client who wants TLS to start ssl.
    %% The OTP 18 time api is also called if it exists, so that the
    %% same code can be run on older releases.
    {FromMod, ToMod} == {diameter_tcp, ssl}
        orelse (FromMod == diameter_lib
                andalso Rel < 18
                andalso lists:member(To, time_api())).

%% New time api in OTP 18.
time_api() ->
    [{erlang, F, A} || {F,A} <- [{convert_time_unit,3},
                                 {monotonic_time,0},
                                 {monotonic_time,1},
                                 {system_time,0},
                                 {system_time,1},
                                 {time_offset,0},
                                 {time_offset,1},
                                 {timestamp,0},
                                 {unique_integer,0},
                                 {unique_integer,1}]]
        ++ [{os, system_time, 0},
            {os, system_time, 1}].

release() ->
    Rel = erlang:system_info(otp_release),
    try list_to_integer(Rel) of
        N -> N
    catch
        error:_ ->
            0  %% aka < 17
    end.

unversion(App) ->
    {Name, [$-|Vsn]} = lists:splitwith(fun(C) -> C /= $- end, App),
    true = is_app(Name), %% assert
    Vsn = vsn_str(Vsn),  %%
    Name.

app('$M_EXPR') -> %% could be anything but assume it's ok
    "erts";
app(Mod) ->
    case code:which(Mod) of
        preloaded ->
            "erts";
        Reason when is_atom(Reason) ->
            error({Reason, Mod});
        Path ->
            %% match to identify an unexpectedly short path
            {_, _, [_,_,_|_] = Split} = {Mod, Path, filename:split(Path)},
            unversion(lists:nth(3, lists:reverse(Split)))
    end.

add_application(XRef, App) ->
    ?AL("add_application -> get lib dir for app ~p", [App]),
    LibDir = code:lib_dir(App),
    ?AL("add_application -> [xref] add lib dir:"
        "~n   ~p", [LibDir]),
    {ok, App} = xref:add_application(XRef, LibDir, []).

make_name(Suf) ->
    list_to_atom("diameter_" ++ atom_to_list(Suf)).


%% ===========================================================================
%% # relup/1
%%
%% Ensure that we can generate release upgrade files using our appup file.
%% ===========================================================================

relup({App, Config}) ->
    i("relup -> entry with"
      "~n   App:    ~p"
      "~n   Config: ~p", [App, Config]),

    [{Vsn, Up, Down}] = ?CONSULT(diameter, appup),
    true = is_vsn(Vsn),

    i("relup -> "
      "~n   Vsn:  ~p"
      "~n   Up:   ~p"
      "~n   Down: ~p", [Vsn, Up, Down]),

    Rel = [{erts, erlang:system_info(version)}
           | [{A, appvsn(A)} || A <- [sasl | fetch(applications, App)]]],

    i("relup -> "
      "~n   Rel: ~p", [Rel]),

    Dir = fetch(priv_dir, Config),

    i("relup -> verify path"
      "~n   Dir: ~p", [Dir]),
    verify_path(Dir),

    i("relup -> "
      "~n   Dir: "
      "~n      ~s"
      "~n   File info (dir): "
      "~n      ~s", [Dir, file_info(Dir)]),

    Name = write_rel(Dir, Rel, Vsn),
    i("relup -> written"
      "~n   Name: "
      "~n      ~s", [Name]),
    UpFrom = acc_rel(Dir, Rel, Up),
    i("relup -> "
      "~n   UpFrom: ~p", [UpFrom]),
    DownTo = acc_rel(Dir, Rel, Down),
    i("relup -> "
      "~n   DownTo: ~p", [DownTo]),

    {[], []} = {UpFrom -- DownTo, DownTo -- UpFrom},
    [[], []] = [S -- sets:to_list(sets:from_list(S))
                || S <- [UpFrom, DownTo]],

    i("relup -> try make relup"),
    {ok, _, _, []} = systools:make_relup(Name, UpFrom, DownTo, [{path, [Dir]},
                                                                {outdir, Dir},
                                                                silent]);

relup(Config) ->
    run(Config, [relup]).


verify_path(Path) ->
    Components = filename:split(filename:absname(Path)),
    do_verify_path(Components).

do_verify_path([]) ->
    exit(not_a_path);
do_verify_path([Root|Components]) ->
    do_verify_path(Root, Components).

do_verify_path(Path, []) ->
    case file:read_file_info(Path) of
        {ok, #file_info{type   = directory,
                        access = Access}} ->
            i("do_verify_path -> (final) directory ok:"
              "~n   Path:   ~p"
              "~n   Access: ~p", [Path, Access]),
            ok;
        {ok, #file_info{type   = Type,
                        access = Access}} ->
            i("do_verify_path -> (final) unexpected type: "
              "~n   Path:   ~p"
              "~n   Type:   ~p"
              "~n   Access: ~p", [Path, Type, Access]),
            exit({not_dir, Path, Type, Access});
        {error, Reason} ->
            i("do_verify_path -> failed reading file info: "
              "~n   Path:   ~p"
              "~n   Reason: ~p", [Path, Reason]),
            exit({read_file_info, Path, Reason})
    end;
do_verify_path(Path, [Component|Components]) ->
    case file:read_file_info(Path) of
        {ok, #file_info{type   = directory,
                        access = Access}} ->
            i("do_verify_path -> directory ok: "
              "~n   Path:   ~p"
              "~n   Access: ~p", [Path, Access]),
            do_verify_path(filename:absname_join(Path, Component),
                           Components);
        {ok, #file_info{type   = Type,
                        access = Access}} ->
            i("do_verify_path -> unexpected type: "
              "~n   Path:   ~p"
              "~n   Type:   ~p"
              "~n   Access: ~p", [Path, Type, Access]),
            exit({not_dir, Path, Type, Access});
        {error, Reason} ->
            i("do_verify_path -> failed reading file info: "
              "~n   Path:   ~p"
              "~n   Reason: ~p", [Path, Reason]),
            exit({read_file_info, Path, Reason})
    end.
            

file_info(Path) ->
    case file:read_file_info(Path) of
        {ok, Info} ->
            f("~p", [Info]);
        {error, Reason} ->
            f("error: ~p", [Reason])
    end.

f(F, A) ->
    lists:flatten(io_lib:format(F, A)).

acc_rel(Dir, Rel, List) ->
    lists:map(fun({V,_}) -> write_rel(Dir, Rel, V) end, List).

%% Write a rel file and return its name.
write_rel(Dir, [Erts | Apps], Vsn) ->
    VS   = vsn_str(Vsn),
    Name = "diameter_test_" ++ VS,
    File = filename:join([Dir, Name ++ ".rel"]),
    i("write_rel -> attempt write rel file:"
      "~n   Dir:  ~p"
      "~n   File: ~p"
      "~n   File name length: ~p"
      "~n   Erts: ~p"
      "~n   Apps: ~p"
      "~n   Vsn:  ~p (~p)",
      [Dir, File, length(File), Erts, Apps, Vsn, VS]),
    ok = write_file(File,
                    {release,
                     {"diameter " ++ VS ++ " test release", VS},
                     Erts,
                     Apps}),
    Name.


%% ===========================================================================
%% ===========================================================================

fetch(Key, List) ->
    {Key, {Key, Val}} = {Key, lists:keyfind(Key, 1, List)}, %% useful badmatch
    Val.

write_file(Path, T) ->
    file:write_file(Path, io_lib:format("~p.", [T])).

%% Is a version string of the expected form?
is_vsn(V) ->
    V = vsn_str(V),
    true.

%% Turn a from/to version in appup to a version string after ensuring
%% that it's valid version number of regexp. In the regexp case, the
%% regexp itself becomes the version string since there's no
%% requirement that a version in appup be anything but a string. The
%% restrictions placed on string-valued version numbers (that they be
%% '.'-separated integers) are our own.

vsn_str(S)
  when is_list(S) ->
    {_, match}   = {S, match(S, "^(0|[1-9][0-9]*)(\\.(0|[1-9][0-9]*))*$")},
    {_, nomatch} = {S, match(S, "\\.0\\.0$")},
    S;

vsn_str(B)
  when is_binary(B) ->
    {ok, _} = re:compile(B),
    %% Check if its a wildcard version: "1\\.."
    Str = binary_to_list(B),
    case lists:reverse(Str) of
        [$*, $., $., $\\ | Rest] ->
            lists:reverse(Rest);
        _ ->
            Str
    end.

match(S, RE) ->
    re:run(S, RE, [{capture, none}]).

%% Is an application name of the expected form?
is_app(S)
  when is_list(S) ->
    {_, match} = {S, match(S, "^([a-z]([a-z_]*|[a-zA-Z]*))$")},
    true.


%% ===========================================================================

i(F) ->
    i(F, []).

i(F, A) when is_list(F) andalso is_list(A) ->
    io:format(F ++ "~n", A). 
