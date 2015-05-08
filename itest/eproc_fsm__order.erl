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
%%  Example FSM implementation, that uses `eproc_router`.
%%
%%  States:
%%
%%    * []              --create--> [pending]
%%    * [pending]       --process--> [delivering]
%%    * [delivering]    --delivered--> [completed]
%%    * [completed]     -- final
%%
-module(eproc_fsm__order).
-behaviour(eproc_fsm).
-compile([{parse_transform, lager_transform}]).
-export([create/3, process/1, delivered/1]).
-export([init/1, init/2, handle_state/3, terminate/3, code_change/4, format_status/2]).
-include_lib("eproc_core/include/eproc.hrl").

-define(ORDER_KEY(O),    {?MODULE, order, O}).
-define(DELIVERY_KEY(D), {?MODULE, delivery, D}).


%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Create new order.
%%
create(OrderId, CustNr, Items) ->
    StartOpts = [{register, both}],
    CreateOpts = [
        {start_spec, {default, StartOpts}},
        {name, {?MODULE, OrderId}}
    ],
    Args = {OrderId, CustNr},
    Event = {create, Items},
    {ok, _FsmRef, Reply} = eproc_fsm:sync_send_create_event(?MODULE, Args, Event, CreateOpts),
    Reply.


%%
%%  Process the order.
%%  Returns a delivery id.
%%
process(OrderId) ->
    eproc_fsm:sync_send_event({key, ?ORDER_KEY(OrderId)}, process).


%%
%%  Mark order as delivered.
%%
delivered(DeliveryId) ->
    eproc_fsm:sync_send_event({key, ?DELIVERY_KEY(DeliveryId)}, delivered).



%% =============================================================================
%%  Internal data structures.
%% =============================================================================

-record(state, {
    order_id,
    cust_nr,
    items = []
}).



%% =============================================================================
%%  Callbacks for eproc_fsm.
%% =============================================================================

%%
%%  FSM init.
%%
init({OrderId, CustNr}) ->
    {ok, #state{
        order_id = OrderId,
        cust_nr = CustNr
    }}.


%%
%%  Runtime init.
%%
init(_StateName, _StateData) ->
    ok.


%%
%%  The initial state.
%%
handle_state([], {sync, _From, {create, Items}}, StateData = #state{order_id = OrderId, cust_nr = CustNr}) ->
    ok = eproc_meta:add_tag(OrderId, order_id),
    ok = eproc_meta:add_tag(CustNr, cust_nr),
    ok = eproc_router:add_key(?ORDER_KEY(OrderId), []),
    {reply_next, ok, [pending], StateData#state{items = Items}};


%%
%%  The `pending` state.
%%  The sync option is not necessary here.
%%
handle_state([pending], {entry, _PrevState}, StateData) ->
    ok = eproc_timer:set({1, hour}, timeout, [pending]),
    {ok, StateData};

handle_state([pending], {sync, _From, process}, StateData) ->
    DeliveryId = {delivery, erlang:node(), erlang:now()},
    ok = eproc_router:add_key(?DELIVERY_KEY(DeliveryId), [], [sync]),
    {reply_next, {ok, DeliveryId}, [delivering], StateData};

handle_state([pending], {timer, timeout}, StateData) ->
    {final_state, [expired], StateData};

handle_state([pending], {exit, _NextState}, StateData) ->
    {ok, StateData};


%%
%%  The `delivering` state.
%%
handle_state([delivering], {entry, _PrevState}, StateData) ->
    {ok, StateData};

handle_state([delivering], {sync, _From, delivered}, StateData) ->
    {reply_final, {ok, completed}, [completed], StateData};

handle_state([delivering], {exit, _NextState}, StateData) ->
    {ok, StateData}.


%%
%%
%%
terminate(_Reason, _StateName, _StateData) ->
    ok.


%%
%%
%%
code_change(_OldVsn, StateName, StateData, _Extra) ->
    {ok, StateName, StateData}.


%%
%%
%%
format_status(_Opt, State) ->
    State.



%% =============================================================================
%%  Internal functions.
%% =============================================================================


