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

%%
%%  Testcases for `eproc_fsm`.
%%
-module(eproc_test_SUITE).
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([
    test_wait_term/1,
    test_stats/1
]).
-define(namespaced_types, ok).
-include_lib("common_test/include/ct.hrl").
-include_lib("hamcrest/include/hamcrest.hrl").
-include_lib("eproc_core/include/eproc.hrl").


%%
%%  CT API.
%%
all() -> [
    test_wait_term,
    test_stats
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



%% =============================================================================
%%  Testcases.
%% =============================================================================

%%
%%  Test functions of the SEQ FSM, using instance id.
%%
test_wait_term(_Config) ->
    SleepFun = fun() -> timer:sleep(50) end,
    %% Test succesful exits
    FsmToCompletionFun = fun(Ref) ->
        SleepFun(),
        {ok, _} = eproc_fsm__seq:next(Ref),
        SleepFun(),
        ok = eproc_fsm__seq:flip(Ref),
        SleepFun(),
        {ok, _} = eproc_fsm__seq:next(Ref),
        SleepFun(),
        ok = eproc_fsm__seq:close(Ref)
    end,
    FsmToKillFun = fun(Ref) ->
        SleepFun(),
        {ok, _} = eproc_fsm:suspend(Ref, []),
        SleepFun(),
        {ok, _} = eproc_fsm:resume(Ref, []),
        SleepFun(),
        {ok, _} = eproc_fsm:kill(Ref, [])
    end,
    RunTestFun = fun(FunsToRun) ->
        FsmRefs = lists:map(fun(FunToRun) ->
            {ok, Ref} = eproc_fsm__seq:new(),
            erlang:spawn(fun() -> FunToRun(Ref) end),
            Ref
        end, FunsToRun),
        FsmFilters = [{id, lists:map(fun({inst, InstId}) -> InstId end, FsmRefs)}],
        ok = eproc_test:wait_term(FsmFilters, {1,s}),
        lists:foreach(fun(Ref) ->
            false = eproc_fsm:is_online(Ref)
        end, FsmRefs)
    end,
    RunTestFun([FsmToCompletionFun]),
    RunTestFun([FsmToKillFun]),
    RunTestFun([FsmToCompletionFun, FsmToKillFun]),
    % Test timeout
    {ok, Ref} = eproc_fsm__seq:new(),
    {inst, InstId} = Ref,
    {error, timeout} = eproc_test:wait_term([{id, InstId}], {1,s}),
    {ok, running, [incrementing], _} = eproc_test:get_state({inst, InstId}),
    true = eproc_fsm:is_online(Ref).


%%
%%  Tests if FSM stats are collected
%%
test_stats(_Config) ->
    % Initialise
    ResetStatsFun = fun(Object, Type) -> exometer:reset([eproc_core, Object, eproc_fsm__seq, Type]) end,
    ResetInstStatsFun = fun(Type) -> ResetStatsFun(inst, Type) end,
    lists:foreach(ResetInstStatsFun, [created, started, suspended, resumed, killed, completed]),
    ResetStatsFun(trans, count),
    % ---------
    % Test cases
    % ---------
    {ok, FsmRef1} = eproc_fsm__seq:new(),   % Suspend/resume instance
    {ok, FsmRef2} = eproc_fsm__seq:new(),   % Instance to be completed
    {ok, FsmRef3} = eproc_fsm__seq:new(),   % Instance to kill
    {ok, FsmRef4} = eproc_fsm__seq:new(),   % Instance for transitions
    timer:sleep(5),
    ?assertThat(eproc_stats:get_value(inst, eproc_fsm__seq, started), is(4)),
    ?assertThat(eproc_stats:get_value(trans, eproc_fsm__seq, count), is(4)),
    % Suspend,resume no state change -> no transition
    {ok, FsmRef1} = eproc_fsm:suspend(FsmRef1, []),
    {ok, FsmRef1} = eproc_fsm:resume(FsmRef1, []),
    timer:sleep(5),
    ?assertThat(eproc_stats:get_value(inst, eproc_fsm__seq, started), is(5)),
    ?assertThat(eproc_stats:get_value(trans, eproc_fsm__seq, count), is(4)),
    % Suspend,resume with state changed -> transition
    {ok, FsmRef1} = eproc_fsm:suspend(FsmRef1, []),
    {ok, FsmRef1} = eproc_fsm:resume(FsmRef1, [{state, {set, decrementing, {state, 20}, undefined}}]),
    timer:sleep(5),
    ?assertThat(eproc_stats:get_value(inst, eproc_fsm__seq, started), is(6)),
    ?assertThat(eproc_stats:get_value(trans, eproc_fsm__seq, count), is(5)),
    % Suspend,resume no state change no start -> no transition
    {ok, FsmRef1} = eproc_fsm:suspend(FsmRef1, []),
    {ok, FsmRef1} = eproc_fsm:resume(FsmRef1, [{start, no}]),
    timer:sleep(5),
    ?assertThat(eproc_stats:get_value(inst, eproc_fsm__seq, started), is(6)),
    ?assertThat(eproc_stats:get_value(trans, eproc_fsm__seq, count), is(5)),
    % Instance completion -> final transition
    ok = eproc_fsm__seq:close(FsmRef2),
    timer:sleep(5),
    ?assertThat(eproc_stats:get_value(trans, eproc_fsm__seq, count), is(6)),
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
    timer:sleep(5),
    ?assertThat(eproc_stats:get_value(inst, eproc_fsm__seq, created), is(4)),
    ?assertThat(eproc_stats:get_value(inst, eproc_fsm__seq, started), is(7)),
    ?assertThat(eproc_stats:get_value(inst, eproc_fsm__seq, suspended), is(3)),
    %?assertThat(eproc_stats:get_value(inst, eproc_fsm__seq, resumed), is(?)),
    ?assertThat(eproc_stats:get_value(inst, eproc_fsm__seq, killed), is(1)),
    ?assertThat(eproc_stats:get_value(inst, eproc_fsm__seq, completed), is(2)),
    ?assertThat(eproc_stats:get_value(trans, eproc_fsm__seq, count), is(11)).


