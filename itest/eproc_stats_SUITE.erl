%/--------------------------------------------------------------------
%| Copyright 2013-2016 Erisata, UAB (Ltd.)
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

%%%
%%% Testcases for `eproc_stats` module.
%%%
-module(eproc_stats_SUITE).
-compile([{parse_transform, lager_transform}]).
-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).
-export([
    test_lifecycle_stats/1,
    test_crash_stats/1,
    test_msg_stats/1,
    test_store_stats/1
]).
-define(namespaced_types, ok).
-include_lib("common_test/include/ct.hrl").
-include_lib("hamcrest/include/hamcrest.hrl").
-include_lib("eproc_core/include/eproc.hrl").


%%
%%  CT API.
%%
all() -> [
    test_lifecycle_stats,
    test_crash_stats,
    test_msg_stats,
    test_store_stats
].


%%
%%  CT API, initialization.
%%
init_per_suite(Config) ->
    application:load(lager),
    application:load(eproc_core),
    application:set_env(lager, handlers, [{lager_console_backend, debug}]),
    application:set_env(eproc_core, store, {eproc_store_ets, ref, []}),
    application:set_env(eproc_core, registry, {eproc_reg_gproc, ref, []}),
    {ok, _} = application:ensure_all_started(gproc),
    {ok, _} = application:ensure_all_started(eproc_core),
    {ok, Store} = eproc_store:ref(),
    {ok, Registry} = eproc_registry:ref(),
    [{store, Store}, {registry, Registry} | Config].


%%
%%  CT API, cleanup.
%%
end_per_suite(_Config) ->
    ok = application:stop(gproc),
    ok = application:stop(eproc_core).


%%
%%  Log test case name at start
%%
init_per_testcase(TestCase, Config) ->
    lager:debug("-------------------------------------- ~p start", [TestCase]),
    Config.


%%
%%  Log test case name at end
%%
end_per_testcase(TestCase, _Config) ->
    lager:debug("-------------------------------------- ~p end", [TestCase]),
    ok.



%%% ============================================================================
%%% Testcases.
%%% ============================================================================

%%
%%  Tests if FSM lifecycle stats are collected.
%%
test_lifecycle_stats(_Config) ->
    % Initialise
    ok = eproc_stats:reset(all),
    % ---------
    % Test cases
    {ok, FsmRef1} = eproc_fsm__seq:new(),   % Suspend/resume instance
    {ok, FsmRef2} = eproc_fsm__seq:new(),   % Instance to be completed
    {ok, FsmRef3} = eproc_fsm__seq:new(),   % Instance to kill
    {ok, FsmRef4} = eproc_fsm__seq:new(),   % Instance for transitions
    timer:sleep(5),
    ?assertThat(eproc_stats:get_fsm_stats(inst, eproc_fsm__seq, started), is(4)),
    ?assertThat(eproc_stats:get_fsm_stats(trn, eproc_fsm__seq, count), is(4)),
    % Suspend,resume no state change -> no transition
    {ok, FsmRef1} = eproc_fsm:suspend(FsmRef1, []),
    {ok, FsmRef1} = eproc_fsm:resume(FsmRef1, []),
    timer:sleep(5),
    ?assertThat(eproc_stats:get_fsm_stats(inst, eproc_fsm__seq, started), is(5)),
    ?assertThat(eproc_stats:get_fsm_stats(trn, eproc_fsm__seq, count), is(4)),
    % Suspend,resume with state changed -> transition
    {ok, FsmRef1} = eproc_fsm:suspend(FsmRef1, []),
    {ok, FsmRef1} = eproc_fsm:resume(FsmRef1, [{state, {set, decrementing, {state, 20}, undefined}}]),
    timer:sleep(5),
    ?assertThat(eproc_stats:get_fsm_stats(inst, eproc_fsm__seq, started), is(6)),
    ?assertThat(eproc_stats:get_fsm_stats(trn, eproc_fsm__seq, count), is(5)),
    % Suspend,resume no state change no start -> no transition
    {ok, FsmRef1} = eproc_fsm:suspend(FsmRef1, []),
    {ok, FsmRef1} = eproc_fsm:resume(FsmRef1, [{start, no}]),
    timer:sleep(5),
    ?assertThat(eproc_stats:get_fsm_stats(inst, eproc_fsm__seq, started), is(6)),
    ?assertThat(eproc_stats:get_fsm_stats(trn, eproc_fsm__seq, count), is(5)),
    % Instance completion -> final transition
    ok = eproc_fsm__seq:close(FsmRef2),
    timer:sleep(5),
    ?assertThat(eproc_stats:get_fsm_stats(trn, eproc_fsm__seq, count), is(6)),
    % Instance kill -> no transition
    {ok, FsmRef3} = eproc_fsm:kill(FsmRef3, []),
    % Generate transitions
    eproc_fsm__seq:next(FsmRef4),
    eproc_fsm__seq:skip(FsmRef4),
    eproc_fsm__seq:flip(FsmRef4),
    eproc_fsm__seq:next(FsmRef4),
    eproc_fsm__seq:last(FsmRef4),
    % Start resuming instance
    {ok, _Pid} = eproc_fsm:start_link(FsmRef1, []),
    % ------------
    % Test results
    timer:sleep(50),
    ?assertThat(eproc_stats:get_fsm_stats(inst, eproc_fsm__seq, created), is(4)),
    ?assertThat(eproc_stats:get_fsm_stats(inst, eproc_fsm__seq, started), is(7)),
    ?assertThat(eproc_stats:get_fsm_stats(inst, eproc_fsm__seq, suspended), is(3)),
    ?assertThat(eproc_stats:get_fsm_stats(inst, eproc_fsm__seq, resumed), is(3)),
    ?assertThat(eproc_stats:get_fsm_stats(inst, eproc_fsm__seq, killed), is(1)),
    ?assertThat(eproc_stats:get_fsm_stats(inst, eproc_fsm__seq, completed), is(2)),
    ?assertThat(eproc_stats:get_fsm_stats(inst, eproc_fsm__seq, crashed), is(0)),
    ?assertThat(eproc_stats:get_fsm_stats(trn,  eproc_fsm__seq, count), is(11)).


%%
%%  Check, if crashes are detected and counted.
%%
test_crash_stats(_Config) ->
    ok = eproc_stats:reset(all),
    {ok, FsmRef} = eproc_fsm__cache:new(),
    ok = eproc_fsm__cache:crash(FsmRef),
    ok = eproc_fsm__cache:stop(FsmRef),
    % ------------
    % Test results
    timer:sleep(50),
    ?assertThat(eproc_stats:get_fsm_stats(inst, eproc_fsm__cache, crashed), is(1)),
    ok.


%%
%%  Check if messages are counted correctly.
%%
test_msg_stats(_Config) ->
    ok = eproc_stats:reset(all),
    {ok, P1} = eproc_fsm__chain:new(),      %               1 in casts
    {ok, P2} = eproc_fsm__chain:new(P1),    %               1 in casts
    {ok, P3} = eproc_fsm__chain:new(P2),    %               1 in casts
    ok = timer:sleep(50),
    0 = eproc_fsm__chain:sum(P3, 2),        % 3 in calls,               2 out calls.
    ok = eproc_fsm__chain:add(P3, 1, 2),    %               3 in casts,              2 out cast.
    ok = eproc_fsm__chain:add(P3, 1, 1),    %               2 in casts,              1 out cast.
    5 = eproc_fsm__chain:sum(P3, 2),        % 3 in calls,               2 out calls.
    3 = eproc_fsm__chain:sum(P2, 1),        % 2 in calls,               1 out calls.
    ok = eproc_fsm__chain:stop(P3),         %               1 in casts
    ok = eproc_fsm__chain:stop(P2),         %               1 in casts
    ok = eproc_fsm__chain:stop(P1),         %               1 in casts
    ok = timer:sleep(50),
    11 = eproc_stats:get_fsm_stats(msg, eproc_fsm__chain, in_async),
    8  = eproc_stats:get_fsm_stats(msg, eproc_fsm__chain, in_sync),
    3  = eproc_stats:get_fsm_stats(msg, eproc_fsm__chain, out_async),
    5  = eproc_stats:get_fsm_stats(msg, eproc_fsm__chain, out_sync),
    11 = eproc_stats:get_fsm_stats(msg, '_', in_async),
    8  = eproc_stats:get_fsm_stats(msg, '_', in_sync),
    3  = eproc_stats:get_fsm_stats(msg, '_', out_async),
    5  = eproc_stats:get_fsm_stats(msg, '_', out_sync),
    0  = eproc_stats:get_fsm_stats(inst, '_', crashed),
    ok.


%%
%%  Check if store statistics are collected.
%%
test_store_stats(_Config) ->
    % Initialise
    ok = eproc_stats:reset(all),
    ?assertThat(eproc_stats:get_store_stats(add_instance, mean), is(0)),
    % ---------
    % Test cases
    {ok, FsmRef} = eproc_fsm__seq:new(),   % Suspend/resume instance
    timer:sleep(5),
    {ok, _} = eproc_fsm__seq:next(FsmRef),
    ok = eproc_fsm__seq:close(FsmRef),
    timer:sleep(5),
    % ------------
    % Test results
    timer:sleep(50),
    ?assertThat(eproc_stats:get_store_stats(add_instance, mean), greater_than(0)),
    ok.


