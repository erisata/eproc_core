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

%%
%%  Testcases for `eproc_fsm`.
%%
-module(eproc_fsm_SUITE).
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([
    test_simple_unnamed/1,
    test_simple_named/1,
    test_suspend_resume/1
]).
-include_lib("common_test/include/ct.hrl").
-include("eproc.hrl").


%%
%%  CT API.
%%
all() -> [
    test_simple_unnamed,
    test_simple_named,
    test_suspend_resume
    ].


%%
%%  CT API, initialization.
%%
init_per_suite(Config) ->
    application:load(lager),
    application:load(eproc_core),
    application:set_env(lager, handlers, [{lager_console_backend, debug}]),
    application:set_env(eproc_core, store, {eproc_store_ets, []}),
    application:set_env(eproc_core, registry, {eproc_reg_gproc, []}),
    {ok, _} = application:ensure_all_started(gproc),
    {ok, _} = application:ensure_all_started(eproc_core),
    {ok, Store} = eproc_registry:ref(),
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
test_simple_unnamed(_Config) ->
    {ok, Seq} = eproc_fsm__seq:new(),
    {ok, 1} = eproc_fsm__seq:next(Seq),
    {ok, 2} = eproc_fsm__seq:next(Seq),
    {ok, 2} = eproc_fsm__seq:get(Seq),
    ok      = eproc_fsm__seq:flip(Seq),
    {ok, 1} = eproc_fsm__seq:next(Seq),
    {ok, 0} = eproc_fsm__seq:next(Seq),
    ok      = eproc_fsm__seq:flip(Seq),
    {ok, 1} = eproc_fsm__seq:next(Seq),
    ok      = eproc_fsm__seq:reset(Seq),
    ok      = eproc_fsm__seq:skip(Seq),
    ok      = eproc_fsm__seq:skip(Seq),
    true    = eproc_fsm__seq:exists(Seq),
    {ok, 2} = eproc_fsm__seq:last(Seq),
    false   = eproc_fsm__seq:exists(Seq),
    ok.

%%
%%  Test functions of the SEQ FSM, using FSM name.
%%
test_simple_named(_Config) ->
    {ok, _} = eproc_fsm__seq:named(test_simple_named),
    {ok, 1} = eproc_fsm__seq:next(test_simple_named),
    {ok, 2} = eproc_fsm__seq:next(test_simple_named),
    {ok, 3} = eproc_fsm__seq:next(test_simple_named),
    true    = eproc_fsm__seq:exists(test_simple_named),
    ok      = eproc_fsm__seq:close(test_simple_named),
    false   = eproc_fsm__seq:exists(test_simple_named),
    ok.


%%
%%  Test, if FSM can be suspended and then resumed.
%%
test_suspend_resume(_Config) ->
    {ok, Seq} = eproc_fsm__seq:new(),
    {ok, 1}   = eproc_fsm__seq:next(Seq),
    %% Suspend
    true      = eproc_fsm__seq:exists(Seq),
    {ok, Seq} = eproc_fsm:suspend(Seq, []),
    false     = eproc_fsm__seq:exists(Seq),
    %% Resume without state change
    {ok, Seq} = eproc_fsm:resume(Seq, []),
    true      = eproc_fsm__seq:exists(Seq),
    {ok, 1}   = eproc_fsm__seq:get(Seq),
    %% Suspend and resume with updated state.
    {ok, Seq} = eproc_fsm:suspend(Seq, []),
    false     = eproc_fsm__seq:exists(Seq),
    {ok, Seq} = eproc_fsm:resume(Seq, [{state, {set, [incrementing], {state, 100}, []}}]),
    true      = eproc_fsm__seq:exists(Seq),
    {ok, 100} = eproc_fsm__seq:get(Seq),
    %% Terminate FSM.
    ok        = eproc_fsm__seq:close(Seq),
    false     = eproc_fsm__seq:exists(Seq),
    ok.


