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
%%% Testcases for EProc FSM test support functions.
%%%
-module(eproc_test_SUITE).
-compile([{parse_transform, lager_transform}]).
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([
    test_wait_term/1
]).
-define(namespaced_types, ok).
-include_lib("common_test/include/ct.hrl").
-include_lib("hamcrest/include/hamcrest.hrl").
-include_lib("eproc_core/include/eproc.hrl").


%%
%%  CT API.
%%
all() -> [
    test_wait_term
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
    {ok, running, incrementing, _} = eproc_test:get_state({inst, InstId}),
    true = eproc_fsm:is_online(Ref).


