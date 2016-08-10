%/--------------------------------------------------------------------
%| Copyright 2013-2015 Erisata, UAB (Ltd.)
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
-module(eproc_limits_tests).
-compile([{parse_transform, lager_transform}]).
-define(DEBUG, true).
-include_lib("eunit/include/eunit.hrl").
-include("eproc.hrl").

%%
%%  Returns test fixture. Actual tests are the functions starting with `test_`.
%%
main_test_() ->
    Tests = fun (PID) -> [
        test_empty(PID),
        test_series_single(PID),
        test_series_single_multi_fail(PID),
        test_series_multi(PID),
        test_rate_single(PID),
        test_rate_multi(PID),
        test_mixed_limit(PID),
        test_multi_limit(PID),
        test_delay_const(PID),
        test_delay_exp(PID),
        test_delay_mixed(PID),
        test_delay_multi(PID),
        test_delay_limit_series(PID),
        test_delay_limit_rate(PID),
        test_delay_limit_multi(PID),
        test_setup_update(PID),
        test_reset_single(PID),
        test_reset_all(PID),
        test_cleanup_single(PID),
        test_cleanup_all(PID)
    ] end,
    {setup, fun setup/0, fun cleanup/1, Tests}.

setup() ->
    {ok, PID} = eproc_limits:start_link(),
    PID.

cleanup(PID) ->
    erlang:unlink(PID),
    erlang:exit(PID, normal).


%%
%%  Check if empty spec works.
%%
test_empty(_PID) ->
    Proc = ?MODULE,
    Name = ?LINE,
    ok = eproc_limits:setup(Proc, Name, undefined),
    TestFun = fun (_, Prev) ->
        This = ok =:= eproc_limits:notify(Proc, Name, 1),
        This and Prev
    end,
    Resp = lists:foldl(TestFun, true, lists:seq(1, 1000)),
    ok = eproc_limits:cleanup(Proc, Name),
    ?_assertEqual(true, Resp).


%%
%%  Check is single `series` limit works.
%%
test_series_single(_PID) ->
    Proc = ?MODULE,
    Name = ?LINE,
    ok  = eproc_limits:setup(Proc, Name, {series, some, 3, {150, ms}, notify}),
    R11 = eproc_limits:notify(Proc, Name, 1),
    R12 = eproc_limits:notify(Proc, Name, 1),
    R13 = eproc_limits:notify(Proc, Name, 1),
    R14 = eproc_limits:notify(Proc, Name, 1),
    timer:sleep(200),
    R21 = eproc_limits:notify(Proc, Name, 1),
    R22 = eproc_limits:notify(Proc, Name, 1),
    R23 = eproc_limits:notify(Proc, Name, 1),
    R24 = eproc_limits:notify(Proc, Name, 1),
    ok  = eproc_limits:cleanup(Proc, Name),
    ?_assertMatch(
        [ok, ok, ok, {reached, [some]}, ok, ok, ok, {reached, [some]}],
        [R11, R12, R13, R14, R21, R22, R23, R24]
    ).


%%
%%  Check is single `series` limit works, if there are several fails during NewAfter time.
%%
test_series_single_multi_fail(_PID) ->
    Proc = ?MODULE,
    Name = ?LINE,
    ok  = eproc_limits:setup(Proc, Name, {series, some, 3, {150, ms}, notify}),
    R11 = eproc_limits:notify(Proc, Name, 1),
    R12 = eproc_limits:notify(Proc, Name, 1),
    R13 = eproc_limits:notify(Proc, Name, 1),
    R14 = eproc_limits:notify(Proc, Name, 1),
    timer:sleep(100),
    R15 = eproc_limits:notify(Proc, Name, 1),
    timer:sleep(100),
    R21 = eproc_limits:notify(Proc, Name, 1),
    R22 = eproc_limits:notify(Proc, Name, 1),
    R23 = eproc_limits:notify(Proc, Name, 1),
    R24 = eproc_limits:notify(Proc, Name, 1),
    ok  = eproc_limits:cleanup(Proc, Name),
    ?_assertMatch(
        [ok, ok, ok, {reached, [some]}, {reached, [some]}, ok, ok, ok, {reached, [some]}],
        [R11, R12, R13, R14, R15, R21, R22, R23, R24]
    ).


%%
%%  Check is multiple `series` limits works.
%%
test_series_multi(_PID) ->
    Proc = ?MODULE,
    Name = ?LINE,
    ok = eproc_limits:setup(Proc, Name, [
        {series, short, 3, {150, ms}, notify},
        {series, long, 5, {1, hour}, notify}
    ]),
    R11 = eproc_limits:notify(Proc, Name, 1),
    R12 = eproc_limits:notify(Proc, Name, 1),
    R13 = eproc_limits:notify(Proc, Name, 1),
    R14 = eproc_limits:notify(Proc, Name, 1),
    timer:sleep(200),
    R21 = eproc_limits:notify(Proc, Name, 1),
    R22 = eproc_limits:notify(Proc, Name, 1),
    R23 = eproc_limits:notify(Proc, Name, 1),
    R24 = eproc_limits:notify(Proc, Name, 1),
    ok  = eproc_limits:cleanup(Proc, Name),
    ?_assertMatch(
        [ok, ok, ok, {reached, [short]}, ok, {reached, [long]}, {reached, [long]}, {reached, [short, long]}],
        [R11, R12, R13, R14, R21, R22, R23, R24]
    ).


%%
%%  Check is single `rate` limit works.
%%
test_rate_single(_PID) ->
    Proc = ?MODULE,
    Name = ?LINE,
    ok  = eproc_limits:setup(Proc, Name, {rate, some, 3, {150, ms}, notify}),
    R11 = eproc_limits:notify(Proc, Name, 1),
    R12 = eproc_limits:notify(Proc, Name, 1),
    R13 = eproc_limits:notify(Proc, Name, 1),
    R14 = eproc_limits:notify(Proc, Name, 1),
    timer:sleep(200),
    R21 = eproc_limits:notify(Proc, Name, 1),
    R22 = eproc_limits:notify(Proc, Name, 1),
    R23 = eproc_limits:notify(Proc, Name, 1),
    R24 = eproc_limits:notify(Proc, Name, 1),
    ok  = eproc_limits:cleanup(Proc, Name),
    ?_assertMatch(
        [ok, ok, ok, {reached, [some]}, ok, ok, ok, {reached, [some]}],
        [R11, R12, R13, R14, R21, R22, R23, R24]
    ).


%%
%%  Check is multiple `rate` limits works.
%%
test_rate_multi(_PID) ->
    Proc = ?MODULE,
    Name = ?LINE,
    ok = eproc_limits:setup(Proc, Name, [
        {rate, short, 3, {150, ms}, notify},
        {rate, long,  5, {1, s},    notify}
    ]),
    R1 = eproc_limits:notify(Proc, Name, 1), timer:sleep(60),
    R2 = eproc_limits:notify(Proc, Name, 1), timer:sleep(60),
    R3 = eproc_limits:notify(Proc, Name, 1), timer:sleep(60),
    R4 = eproc_limits:notify(Proc, Name, 1), timer:sleep(60),
    R5 = eproc_limits:notify(Proc, Name, 1), timer:sleep(60),
    R6 = eproc_limits:notify(Proc, Name, 1), timer:sleep(60),
    R7 = eproc_limits:notify(Proc, Name, 1),
    R8 = eproc_limits:notify(Proc, Name, 1), timer:sleep(200),
    R9 = eproc_limits:notify(Proc, Name, 1),
    ok = eproc_limits:cleanup(Proc, Name),
    ?_assertMatch(
        [ok, ok, ok, ok, ok, {reached, [long]}, {reached, [long]}, {reached, [short, long]}, {reached, [long]}],
        [R1, R2, R3, R4, R5, R6, R7, R8, R9]
    ).


%%
%%  Check if `series` and `rate` limits works together.
%%
test_mixed_limit(_PID) ->
    Proc = ?MODULE,
    Name = ?LINE,
    ok = eproc_limits:setup(Proc, Name, [
        {series, short, 3, {150, ms}, notify},
        {rate,   long,  5, {1, s},    notify}
    ]),
    R1 = eproc_limits:notify(Proc, Name, 1), timer:sleep(60),
    R2 = eproc_limits:notify(Proc, Name, 1), timer:sleep(60),
    R3 = eproc_limits:notify(Proc, Name, 1), timer:sleep(60),
    R4 = eproc_limits:notify(Proc, Name, 1), timer:sleep(60),
    R5 = eproc_limits:notify(Proc, Name, 1), timer:sleep(60),
    R6 = eproc_limits:notify(Proc, Name, 1), timer:sleep(60),
    R7 = eproc_limits:notify(Proc, Name, 1),
    R8 = eproc_limits:notify(Proc, Name, 1), timer:sleep(200),
    R9 = eproc_limits:notify(Proc, Name, 1),
    ok = eproc_limits:cleanup(Proc, Name),
    ?_assertMatch(
        [ok, ok, ok,
            {reached, [short]}, {reached, [short]}, {reached, [short, long]},
            {reached, [short, long]}, {reached, [short, long]}, {reached, [long]}],
        [R1, R2, R3, R4, R5, R6, R7, R8, R9]
    ).


%%
%%  Check if notify with several counters works.
%%
test_multi_limit(_PID) ->
    Proc = ?MODULE,
    Name1 = ?LINE,
    Name2 = ?LINE,
    ok = eproc_limits:setup(Proc, Name1, {series, some, 1, {150, ms}, notify}),
    ok = eproc_limits:setup(Proc, Name2, {series, some, 3, {150, ms}, notify}),
    R1 = eproc_limits:notify(Proc, [{Name1, 1}, {Name2, 1}]),
    R2 = eproc_limits:notify(Proc, [{Name1, 1}, {Name2, 1}]),
    R3 = eproc_limits:notify(Proc, [{Name1, 1}, {Name2, 1}]),
    R4 = eproc_limits:notify(Proc, [{Name1, 1}, {Name2, 1}]),
    ok = eproc_limits:cleanup(Proc),
    ?_assertMatch(
        [
            ok,
            {reached, [{Name1, [some]}]},
            {reached, [{Name1, [some]}]},
            {reached, [{Name1, [some]}, {Name2, [some]}]}
        ],
        [R1, R2, R3, R4]
    ).


%%
%%  Check if constant delay works.
%%
test_delay_const(_PID) ->
    Proc = ?MODULE,
    Name = ?LINE,
    ok = eproc_limits:setup(Proc, Name, {series, some, 0, {1, s}, {delay, {50, ms}}}),
    {delay, D1} = eproc_limits:notify(Proc, Name, 1),
    {delay, D2} = eproc_limits:notify(Proc, Name, 1),
    {delay, D3} = eproc_limits:notify(Proc, Name, 1),
    {delay, D4} = eproc_limits:notify(Proc, Name, 1),
    ok = eproc_limits:cleanup(Proc, Name),
    ?_assertEqual([50, 50, 50, 50], [D1, D2, D3, D4]).


%%
%%  Check if exponential delay works.
%%
test_delay_exp(_PID) ->
    Proc = ?MODULE,
    Name = ?LINE,
    ok = eproc_limits:setup(Proc, Name, {series, some, 0, {1, s}, {delay, 10, 2.0, 80}}),
    {delay, D1} = eproc_limits:notify(Proc, Name, 1),
    {delay, D2} = eproc_limits:notify(Proc, Name, 1),
    {delay, D3} = eproc_limits:notify(Proc, Name, 1),
    {delay, D4} = eproc_limits:notify(Proc, Name, 1),
    {delay, D5} = eproc_limits:notify(Proc, Name, 1),
    {delay, D6} = eproc_limits:notify(Proc, Name, 1),
    ok = eproc_limits:cleanup(Proc, Name),
    ?_assertEqual([10, 20, 40, 80, 80, 80], [D1, D2, D3, D4, D5, D6]).


%%
%%  Check if constant delay works together with exponential.
%%
test_delay_mixed(_PID) ->
    Proc = ?MODULE,
    Name = ?LINE,
    ok = eproc_limits:setup(Proc, Name, [
        {series, some, 0, {1, s}, {delay, 40}},
        {series, some, 0, {1, s}, {delay, 10, 2.0, 160}}
    ]),
    {delay, D1} = eproc_limits:notify(Proc, Name, 1),
    {delay, D2} = eproc_limits:notify(Proc, Name, 1),
    {delay, D3} = eproc_limits:notify(Proc, Name, 1),
    {delay, D4} = eproc_limits:notify(Proc, Name, 1),
    {delay, D5} = eproc_limits:notify(Proc, Name, 1),
    {delay, D6} = eproc_limits:notify(Proc, Name, 1),
    ok = eproc_limits:cleanup(Proc, Name),
    ?_assertEqual([40, 40, 40, 80, 160, 160], [D1, D2, D3, D4, D5, D6]).


%%
%%  Check if notify with several counters works with delays.
%%
test_delay_multi(_PID) ->
    Proc = ?MODULE,
    Name1 = ?LINE,
    Name2 = ?LINE,
    ok = eproc_limits:setup(Proc, Name1, {series, some, 1, {150, ms}, {delay, 100}}),
    ok = eproc_limits:setup(Proc, Name2, {series, some, 3, {150, ms}, {delay, 200}}),
    R1 = eproc_limits:notify(Proc, [{Name1, 1}, {Name2, 1}]),
    R2 = eproc_limits:notify(Proc, [{Name1, 1}, {Name2, 1}]),
    R3 = eproc_limits:notify(Proc, [{Name1, 1}, {Name2, 1}]),
    R4 = eproc_limits:notify(Proc, [{Name1, 1}, {Name2, 1}]),
    ok = eproc_limits:cleanup(Proc),
    ?_assertMatch(
        [ok, {delay, 100}, {delay, 100}, {delay, 200}],
        [R1, R2, R3, R4]
    ).


%%
%%  Check if delays issued (calculated in previous notifications) are not
%%  interleaving with limit conditions in the case of series limit.
%%
test_delay_limit_series(_PID) ->
    Proc = ?MODULE,
    Name = ?LINE,
    ok = eproc_limits:setup(Proc, Name, {series, test, 2, {50, ms}, {delay, 100}}),
    R1 = eproc_limits:notify(Proc, Name, 1), timer:sleep(10),
    R2 = eproc_limits:notify(Proc, Name, 1), timer:sleep(10),
    R3 = eproc_limits:notify(Proc, Name, 1), timer:sleep(10 + 100),
    R4 = eproc_limits:notify(Proc, Name, 1), timer:sleep(10 + 100),
    R5 = eproc_limits:notify(Proc, Name, 1), timer:sleep(10 + 100),
    R6 = eproc_limits:notify(Proc, Name, 1),
    ok = eproc_limits:cleanup(Proc),
    ?_assertMatch(
        [ok, ok, {delay, 100}, {delay, 100}, {delay, 100}, {delay, 100}],
        [R1, R2, R3,           R4,           R5,           R6          ]
    ).


%%
%%  Check if delays issued (calculated in previous notifications) are not
%%  interferring with limit conditions in the case of rate limit.
%%
test_delay_limit_rate(_PID) ->
    Proc = ?MODULE,
    Name = ?LINE,
    ok = eproc_limits:setup(Proc, Name, {rate, test, 2, {50, ms}, {delay, 100}}),
    R1 = eproc_limits:notify(Proc, Name, 1), timer:sleep(10),
    R2 = eproc_limits:notify(Proc, Name, 1), timer:sleep(10),
    R3 = eproc_limits:notify(Proc, Name, 1), timer:sleep(10 + 100),
    R4 = eproc_limits:notify(Proc, Name, 1), timer:sleep(10 + 100),
    R5 = eproc_limits:notify(Proc, Name, 1), timer:sleep(10 + 100),
    R6 = eproc_limits:notify(Proc, Name, 1),
    ok = eproc_limits:cleanup(Proc),
    ?_assertMatch(
        [ok, ok, {delay, 100}, {delay, 100}, {delay, 100}, {delay, 100}],
        [R1, R2, R3,           R4,           R5,           R6          ]
    ).

%%
%%  Check if delays issued (calculated in previous notifications) are not
%%  interferring with limit conditions in the case of multiple limits.
%%
test_delay_limit_multi(_PID) ->
    Proc = ?MODULE,
    Name1 = ?LINE,
    Name2 = ?LINE,
    ok = eproc_limits:setup(Proc, Name1, {series, s1, 4, {50, ms}, {delay, 200}}),
    ok = eproc_limits:setup(Proc, Name2, {series, s2, 2, {50, ms}, {delay, 100}}),
    R1 = eproc_limits:notify(Proc, [{Name1, 1}, {Name2, 1}]), timer:sleep(10),
    R2 = eproc_limits:notify(Proc, [{Name1, 1}, {Name2, 1}]), timer:sleep(10),
    R3 = eproc_limits:notify(Proc, [{Name1, 1}, {Name2, 1}]), timer:sleep(10 + 100),
    R4 = eproc_limits:notify(Proc, [{Name1, 1}, {Name2, 1}]), timer:sleep(10 + 100),
    R5 = eproc_limits:notify(Proc, [{Name1, 1}, {Name2, 1}]),
    ok = eproc_limits:cleanup(Proc),
    ?_assertMatch(
        [ok, ok, {delay, 100}, {delay, 100}, {delay, 200}],
        [R1, R2, R3,           R4,           R5          ]
    ).


%%
%%  Check if setup can be updated.
%%
test_setup_update(_PID) ->
    Proc = ?MODULE,
    Name = ?LINE,
    ok = eproc_limits:setup(Proc, Name, {rate, some, 3, {150, ms}, notify}),
    R1 = eproc_limits:notify(Proc, Name, 1),
    R2 = eproc_limits:notify(Proc, Name, 1),
    R3 = eproc_limits:notify(Proc, Name, 1),
    R4 = eproc_limits:notify(Proc, Name, 1),
    ok = eproc_limits:setup(Proc, Name, {rate, some, 3, {150, ms}, notify}), % Should be ignored.
    R5 = eproc_limits:notify(Proc, Name, 1),
    ok = eproc_limits:setup(Proc, Name, []), % Set new config and reset counters.
    R6 = eproc_limits:notify(Proc, Name, 1),
    R7 = eproc_limits:notify(Proc, Name, 1),
    R8 = eproc_limits:notify(Proc, Name, 1),
    R9 = eproc_limits:notify(Proc, Name, 1),
    ok = eproc_limits:cleanup(Proc, Name),
    ?_assertMatch(
        [ok, ok, ok, {reached, [some]}, {reached, [some]}, ok, ok, ok, ok],
        [R1, R2, R3, R4, R5, R6, R7, R8, R9]
    ).


%%
%%  Check if counter can be reset.
%%
test_reset_single(_PID) ->
    Proc = ?MODULE,
    Name = ?LINE,
    ok  = eproc_limits:setup(Proc, Name, {rate, some, 3, {150, ms}, notify}),
    R11 = eproc_limits:notify(Proc, Name, 1),
    R12 = eproc_limits:notify(Proc, Name, 1),
    R13 = eproc_limits:notify(Proc, Name, 1),
    R14 = eproc_limits:notify(Proc, Name, 1),
    ok  = eproc_limits:reset(Proc, Name),
    R21 = eproc_limits:notify(Proc, Name, 1),
    R22 = eproc_limits:notify(Proc, Name, 1),
    R23 = eproc_limits:notify(Proc, Name, 1),
    R24 = eproc_limits:notify(Proc, Name, 1),
    ok  = eproc_limits:cleanup(Proc, Name),
    ?_assertMatch(
        [ok, ok, ok, {reached, [some]}, ok, ok, ok, {reached, [some]}],
        [R11, R12, R13, R14, R21, R22, R23, R24]
    ).


%%
%%  Check if counter can be reset.
%%
test_reset_all(_PID) ->
    Proc = ?MODULE,
    Name = ?LINE,
    ok  = eproc_limits:setup(Proc, Name, {rate, some, 3, {150, ms}, notify}),
    R11 = eproc_limits:notify(Proc, Name, 1),
    R12 = eproc_limits:notify(Proc, Name, 1),
    R13 = eproc_limits:notify(Proc, Name, 1),
    R14 = eproc_limits:notify(Proc, Name, 1),
    ok  = eproc_limits:reset(Proc),
    R21 = eproc_limits:notify(Proc, Name, 1),
    R22 = eproc_limits:notify(Proc, Name, 1),
    R23 = eproc_limits:notify(Proc, Name, 1),
    R24 = eproc_limits:notify(Proc, Name, 1),
    ok  = eproc_limits:cleanup(Proc, Name),
    ?_assertMatch(
        [ok, ok, ok, {reached, [some]}, ok, ok, ok, {reached, [some]}],
        [R11, R12, R13, R14, R21, R22, R23, R24]
    ).


%%
%%  Check if cleanup of single counter works.
%%
test_cleanup_single(_PID) ->
    Proc = ?MODULE,
    Name = ?LINE,
    ok = eproc_limits:setup(Proc, Name, {series, some, 1000, {1, s}, notify}),
    ok = eproc_limits:notify(Proc, Name, 1),
    ok = eproc_limits:cleanup(Proc, Name),
    ok = eproc_limits:cleanup(Proc, Name),
    ?_assertEqual({error, {not_found, Name}}, eproc_limits:notify(Proc, Name, 1)).


%%
%%  Check if cleanup of all counters of the process works.
%%
test_cleanup_all(_PID) ->
    Proc = ?MODULE,
    Name = ?LINE,
    ok = eproc_limits:setup(Proc, Name, {series, some, 1000, {1, s}, notify}),
    ok = eproc_limits:notify(Proc, Name, 1),
    ok = eproc_limits:cleanup(Proc),
    ok = eproc_limits:cleanup(Proc),
    ?_assertEqual({error, {not_found, Name}}, eproc_limits:notify(Proc, Name, 1)).


