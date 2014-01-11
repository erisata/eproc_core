%/--------------------------------------------------------------------
%| Copyright 2013-2014 Erisata, UAB (Ltd.)
%|
%| Licensed under the Apache License, Version 2.0 (the "License");
%| you may not use this file except in compliance with the License.
%| You may obtain a copy of the License at
%|
%|     http://www.apache.org/licenses/LICENSE-2.0
%|
%| Unless required by applicable law or agreed to in writing, software
%| distributed under the License is distributed on an "AS IS" BASIS,
%| WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%| See the License for the specific language governing permissions and
%| limitations under the License.
%\--------------------------------------------------------------------
-module(eproc_restart_tests).
-compile([{parse_transform, lager_transform}]).
-define(DEBUG, true).
-include_lib("eunit/include/eunit.hrl").
-include("eproc.hrl").

%%
%%  Returns test fixture. Actual tests are the functions starting with `test_`.
%%
main_test_() ->
    Tests = fun (PID) -> [
        test_delay_none(PID),
        test_delay_const(PID),
        test_delay_exp(PID),
        test_fail_never(PID),
        test_fail(PID),
        test_fail_expiry(PID),
        test_cleanup(PID)
    ] end,
    {setup, fun setup/0, fun cleanup/1, Tests}.

setup() ->
    {ok, PID} = eproc_restart:start_link(),
    PID.

cleanup(PID) ->
    erlang:unlink(PID),
    erlang:exit(PID, normal).


%%
%%  Check if delay=none works.
%%
test_delay_none(_PID) ->
    Key = {?MODULE, ?LINE},
    {ElapsedUS, ok} = timer:tc(fun () ->
        ok = eproc_restart:restarted(Key, []),
        ok = eproc_restart:restarted(Key, []),
        ok = eproc_restart:restarted(Key, []),
        ok = eproc_restart:restarted(Key, [{delay, none}]),
        ok = eproc_restart:restarted(Key, [{delay, none}]),
        ok = eproc_restart:restarted(Key, [{delay, none}])
    end),
    ?_assert(ElapsedUS < 10000). % 10 ms


%%
%%  Check if delay=const works.
%%
test_delay_const(_PID) ->
    Key = {?MODULE, ?LINE},
    Delay = {delay, {const, 50}},
    {ElapsedUS, ok} = timer:tc(fun () ->
        ok = eproc_restart:restarted(Key, [Delay]),    % No delay at first restart.
        ok = eproc_restart:restarted(Key, [Delay]),    % Delay 50ms.
        ok = eproc_restart:restarted(Key, [Delay]),    % Delay 50ms.
        ok = eproc_restart:restarted(Key, [Delay]),    % Delay 50ms.
        ok = eproc_restart:restarted(Key, [Delay])     % Delay 50ms.
    end),
    [
        ?_assert(200000 =< ElapsedUS),  % 200 ms
        ?_assert(ElapsedUS < 500000)    % 500 ms
    ].


%%
%%  Check if delay=exp works.
%%
test_delay_exp(_PID) ->
    Key = {?MODULE, ?LINE},
    Delay = {delay, {exp, 10, 1.5}},
    {ElapsedUS, ok} = timer:tc(fun () ->
        ok = eproc_restart:restarted(Key, [Delay]),    % No delay at first restart.
        ok = eproc_restart:restarted(Key, [Delay]),    % Delay of 10ms.
        ok = eproc_restart:restarted(Key, [Delay]),    % Delay of 15ms.
        ok = eproc_restart:restarted(Key, [Delay]),    % Delay of 22ms.
        ok = eproc_restart:restarted(Key, [Delay])     % Delay of 33ms.
    end),
    [
        ?_assert(80000 =< ElapsedUS),   % 80 ms.
        ?_assert(ElapsedUS < 200000)    % 200 ms.
    ].


%%
%%  Check never failing delay.
%%
test_fail_never(_PID) ->
    Key = {?MODULE, ?LINE},
    Opts = [{delay, {const, 1}}, {fail, never}],
    Resp = lists:foldl(fun (_, _) -> eproc_restart:restarted(Key, Opts) end, fail, lists:seq(0, 100)),
    ?_assertEqual(ok, Resp).


%%
%%  Check fail.
%%
test_fail(_PID) ->
    Key = {?MODULE, ?LINE},
    Opts = [{delay, {const, 1}}, {fail, {10, 1000}}],   %% 10 times / 1 second
    Resp = lists:foldl(fun (_, _) -> eproc_restart:restarted(Key, Opts) end, fail, lists:seq(0, 100)),
    ?_assertEqual(fail, Resp).


%%
%%  Check fail delay.
%%
test_fail_expiry(_PID) ->
    Key = {?MODULE, ?LINE},
    Opts = [{delay, {const, 1}}, {fail, {11, 100}}],   %% 11 times / 0.1 second
    Resp1 = lists:foldl(fun (_, _) -> eproc_restart:restarted(Key, Opts) end, fail, lists:seq(0, 10)),
    timer:sleep(100),
    Resp2 = lists:foldl(fun (_, _) -> eproc_restart:restarted(Key, Opts) end, fail, lists:seq(0, 10)),
    Resp3 = lists:foldl(fun (_, _) -> eproc_restart:restarted(Key, Opts) end, fail, lists:seq(0, 10)),
    timer:sleep(100),
    Resp4 = lists:foldl(fun (_, _) -> eproc_restart:restarted(Key, Opts) end, fail, lists:seq(0, 10)),
    [
        ?_assertEqual(ok,   Resp1),
        ?_assertEqual(ok,   Resp2),
        ?_assertEqual(fail, Resp3),
        ?_assertEqual(ok,   Resp4)
    ].


%%
%%  Check if cleanup works.
%%
test_cleanup(_PID) ->
    Key = {?MODULE, ?LINE},
    Opts = [{delay, {const, 1}}, {fail, {11, 100}}],   %% 11 times / 0.1 second
    Resp1 = lists:foldl(fun (_, _) -> eproc_restart:restarted(Key, Opts) end, fail, lists:seq(0, 10)),
    Resp2 = lists:foldl(fun (_, _) -> eproc_restart:restarted(Key, Opts) end, fail, lists:seq(0, 10)),
    ok = eproc_restart:cleanup(Key),
    Resp3 = lists:foldl(fun (_, _) -> eproc_restart:restarted(Key, Opts) end, fail, lists:seq(0, 10)),
    Resp4 = lists:foldl(fun (_, _) -> eproc_restart:restarted(Key, Opts) end, fail, lists:seq(0, 10)),
    ok = eproc_restart:cleanup(Key),
    ok = eproc_restart:cleanup(Key),
    [
        ?_assertEqual(ok,   Resp1),
        ?_assertEqual(fail, Resp2),
        ?_assertEqual(ok,   Resp3),
        ?_assertEqual(fail, Resp4)
    ].


