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
-module(eproc_fsm_SUITE).
-export([all/0, init_per_suite/1, end_per_suite/1]).
-export([
    test_simple_unnamed/1,
    test_simple_named/1,
    test_suspend_resume/1,
    test_kill/1,
    test_rtdata/1,
    test_timers/1,
    test_router_integration/1,
    test_metadata_integration/1
]).
-include_lib("common_test/include/ct.hrl").
-include("eproc.hrl").


%%
%%  CT API.
%%
all() -> [
    test_simple_unnamed,
    test_simple_named,
    test_suspend_resume,
    test_kill,
    test_rtdata,
    test_timers,
    test_router_integration,
    test_metadata_integration
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


%%
%%  Check, if FSM can be killed.
%%
test_kill(_Config) ->
    {ok, Seq} = eproc_fsm__seq:new(),
    true      = eproc_fsm__seq:exists(Seq),
    {ok, Seq} = eproc_fsm:kill(Seq, []),
    false     = eproc_fsm__seq:exists(Seq),
    ok.


%%
%%  Check if FSM runtime data functionality works.
%%
test_rtdata(_Config) ->
    {ok, P} = eproc_fsm__cache:new(),
    {ok, X = {_, _, _}} = eproc_fsm__cache:get(P),
    {ok, X = {_, _, _}} = eproc_fsm__cache:get(P),
    ok = eproc_fsm__cache:crash(P),
    timer:sleep(100),   %% Wait for process to be restarted.
    {ok, Y = {_, _, _}} = eproc_fsm__cache:get(P),
    {ok, Y = {_, _, _}} = eproc_fsm__cache:get(P),
    true = (X =/= Y),
    ok = eproc_fsm__cache:stop(P),
    ok.


%%
%%  Check if timers work.
%%
test_timers(_Config) ->
    {ok, P} = eproc_fsm__sched:start(),
    ok = eproc_fsm__sched:subscribe(P),
    %%  Set timer.
    ok = eproc_fsm__sched:set(P, 100),
    ok = receive tick -> ok after 500 -> timeout end,
    ok = receive tick -> ok after 500 -> timeout end,
    %%  Update timer.
    ok = eproc_fsm__sched:set(P, 400),
    ok = flush_msgs(),
    ok = receive tick -> bad after 300 -> ok end,
    ok = receive tick -> ok after 400 -> timeout end,
    %% Cancel timer by scope.
    ok = eproc_fsm__sched:pause(P),
    ok = flush_msgs(),
    ok = receive tick -> bad after 1000 -> ok end,
    %% Start timer again.
    ok = eproc_fsm__sched:set(P, 100),
    ok = receive tick -> ok after 500 -> timeout end,
    ok = receive tick -> ok after 500 -> timeout end,
    %% Cancel timer explicitly.
    ok = eproc_fsm__sched:cancel(P),
    ok = receive tick -> bad after 1000 -> ok end,
    %% Cleanup.
    ok = eproc_fsm__sched:stop(P),
    ok.


%%
%%  Check if router works with FSM.
%%
test_router_integration(_Config) ->
    OrderId = {order, erlang:node(), erlang:now()},
    ok               = eproc_fsm__order:create(OrderId),
    {ok, DeliveryId} = eproc_fsm__order:process(OrderId),
    {ok, completed}  = eproc_fsm__order:delivered(DeliveryId),
    ok.


%%
%%  Check if metadata tags works with FSM.
%%
test_metadata_integration(_Config) ->
    {ok, []} = eproc_meta:get_instances({tags, [{<<"123">>, <<"cust_nr">>}]}, []),
    {ok, Ref} = eproc_fsm__inquiry:create(123, <<"Unclear invoice lines.">>),
    ok        = eproc_fsm__inquiry:close(Ref, rejected),
    {inst, IID} = Ref,
    {ok, [IID]} = eproc_meta:get_instances({tags, [{<<"123">>,      <<"cust_nr">>   }]}, []),
    {ok, [IID]} = eproc_meta:get_instances({tags, [{<<"rejected">>, <<"resolution">>}]}, []),
    ok.


%%
%%  TODO: Send msg.
%%


%%
%%  Clear msg inbox.
%%
flush_msgs() ->
    receive _ -> flush_msgs()
    after 0 -> ok
    end.

