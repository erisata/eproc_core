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
    test_update/1,
    test_kill/1,
    test_rtdata/1,
    test_timers/1,
    test_timers_after_resume/1,
    test_router_integration/1,
    test_metadata_integration/1,
    test_event_type/1,
    test_orthogonal_states/1
]).
-include_lib("common_test/include/ct.hrl").
-include_lib("eproc_core/include/eproc.hrl").


%%
%%  CT API.
%%
all() -> [
    test_simple_unnamed,
    test_simple_named,
    test_suspend_resume,
    test_update,
    test_kill,
    test_rtdata,
    test_timers,
    test_timers_after_resume,
    test_router_integration,
    test_metadata_integration,
    test_event_type,
    test_orthogonal_states
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
%%  Test, if FSM state update works.
%%
test_update(_Config) ->
    {ok, Seq} = eproc_fsm__seq:new(),
    {ok, 1}   = eproc_fsm__seq:next(Seq),
    %% Update running process
    true      = eproc_fsm__seq:exists(Seq),
    {ok, Seq} = eproc_fsm:update(Seq, undefined, {state, 100}, undefined, []),
    true      = eproc_fsm__seq:exists(Seq),
    {ok, 100} = eproc_fsm__seq:get(Seq),
    %% Update suspended process
    {ok, Seq} = eproc_fsm:suspend(Seq, []),
    false     = eproc_fsm__seq:exists(Seq),
    {ok, Seq} = eproc_fsm:update(Seq, undefined, {state, 200}, undefined, []),
    true      = eproc_fsm__seq:exists(Seq),
    {ok, 200} = eproc_fsm__seq:get(Seq),
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
    %% Check manual firing of the timer.
    ok = eproc_fsm__sched:set(P, {1, year}),
    ok = receive tick -> bad after 1000 -> ok end,
    ok = eproc_timer:trigger(P, {name, main}),
    ok = receive tick -> ok after 500 -> timeout end,
    %% Check manual triggering of the timer event.
    ok = eproc_fsm__sched:set(P, {1, year}),
    ok = receive tick -> bad after 1000 -> ok end,
    ok = eproc_fsm:trigger_event(P, timer, tick, []),
    ok = receive tick -> ok after 500 -> timeout end,
    %% Cleanup.
    ok = eproc_fsm__sched:stop(P),
    ok.


%%
%%  Check if timers are set correctly on fsm start. Especially, if some timer is
%%  created and updated in the same transition.
%%
%%  NOTE: this is a known bug, which this test is supposed to catch. However,
%%  it does not yet successfully reproduce it.
%%
test_timers_after_resume(_Config) ->
    {ok, P} = eproc_fsm__sched:start(),
    ok = eproc_fsm__sched:subscribe(P),
    %%  Set timer.
    ok = eproc_fsm__sched:set_single(P, 10000),
    {ok, P} = eproc_fsm:suspend(P, []),
    ok = timer:sleep(100),  % Wait for async suspend.
    {ok, P} = eproc_fsm:resume(P, []),
    ok = timer:sleep(100),  % Wait for resume.
    true = eproc_fsm:is_online(P),
    {ok, #instance{}} = eproc_store:load_instance(undefined, P),
    ok.


%%
%%  Check if router works with FSM.
%%
test_router_integration(_Config) ->
    OrderId = erlang:phash2({order, erlang:node(), erlang:make_ref()}),
    ok               = eproc_fsm__order:create(OrderId, cust_123, [some, order, lines]),
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
%%  Test, if message types are derived correctly.
%%
test_event_type(Config) ->
    Store = proplists:get_value(store, Config),
    {ok, Seq} = eproc_fsm__seq:new(),
    {ok, 1}   = eproc_fsm__seq:next(Seq),
    {ok, 1}   = eproc_fsm__seq:get(Seq),
    ok        = eproc_fsm__seq:close(Seq),
    false     = eproc_fsm__seq:exists(Seq),
    {ok, #transition{trigger_msg = #msg_ref{type = <<"next">>}}} = eproc_store:get_transition(Store, Seq, 2, all),
    {ok, #transition{trigger_msg = #msg_ref{type = <<"what">>}}} = eproc_store:get_transition(Store, Seq, 3, all),
    ok.


%%
%%  Test orthogonal states.
%%
test_orthogonal_states(_Config) ->
    {ok, Lamp}      = eproc_fsm__lamp:create(),         % It is turned off, when created.
    {ok, [off]}     = eproc_fsm__lamp:events(Lamp),
    ok              = eproc_fsm__lamp:toggle(Lamp),     % Turn it on.
    ok              = eproc_fsm__lamp:toggle(Lamp),     % Turn it off
    {ok, [on, off]} = eproc_fsm__lamp:events(Lamp),
    ok              = eproc_fsm__lamp:break(Lamp),      % Switch state does not change here.
    ok              = eproc_fsm__lamp:fix(Lamp),        % Lamp is turned off, after fixing it.
    ok              = eproc_fsm__lamp:toggle(Lamp),     % Now turn it on.
    {ok, [off, on]} = eproc_fsm__lamp:events(Lamp),
    {ok, {no, on}}  = eproc_fsm__lamp:state(Lamp),
    ok              = eproc_fsm__lamp:recycle(Lamp),
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

