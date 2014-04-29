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
%%  The dispatcher is used to map incoming messages to FSM API function calls.
%%  It is intended to use by connector implementations, that receive external
%%  messages and need to dispatch them to corresponding FSMs.
%%
%%  User modules can implement this behaviour to provide business specific
%%  mapping of messages to FSM function calls.
%%
-module(eproc_dispatcher).
-export([new/2, new/1, dispatch/2]).
-include("eproc.hrl").

-type dispatcher_spec() :: {Module :: module(), Args :: list()}.

-record(state, {
    specs   :: [dispatcher_spec()]
}).


%% =============================================================================
%%  Callback definitions.
%% =============================================================================

%%
%%  This function should process the Event. Typical implementation of this
%%  callback will:
%%
%%    * Recognize the Event by pattern matching,
%%    * Extract keys from the Event,
%%    * Call the corresponding FSM implementation.
%%
%%  Example, when the message routing by key is done in th FSM
%%  implementation (the recommended way):
%%
%%      handle_dispatch({order_update, OrderNr, NewPrice}, _Args) ->
%%          ok = my_order:new_price(OrderNr, NewPrice),
%%          noreply.
%%
%%  Example, when the message routing is performed by the dispatcher
%%  (can be used if some more complicated routing is needed):
%%
%%      handle_dispatch({order_update, OrderNr, NewPrice}, _Args) ->
%%          {ok, [InstId]} = eproc_router:lookup({order, OrderNr}),
%%          ok = my_order:new_price({inst, InstId}, NewPrice),
%%          noreply.
%%
%%      handle_event({order_update, OrderNr, NewPrice}, _Args) ->
%%          eproc_router:lookup_send({order, OrderNr}, fun (FsmRef) ->
%%              ok = my_order:new_price(FsmRef, NewPrice)
%%          end).
%%
%%  This function should return `noreply`, if the call was asynchonous,
%%  `{reply, Reply}` if the call was synchronous, and `unknown` if the
%%  message is not recognized by this callback module.
%%
-callback handle_dispatch(
        Event       :: term(),
        Args        :: term()
    ) ->
        noreply |
        {reply, Reply :: term()} |
        {error, Reason :: term()} |
        unknown.



%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Configute new dispatcher. This function is used by dispatcher clients.
%%  The DispatcherSpec parameter takes a list of module/args pairs.
%%  The specified modules should implement `eproc_dispatcher` behaviour.
%%
%%  No options are currently supported.
%%
-spec new(
        DispatcherSpecs :: [dispatcher_spec()],
        Opts            :: []
    ) ->
        {ok, Dispatcher :: term()}.

new(DispatcherSpecs, _Opts) ->
    lists:foreach(fun ({_M, _A}) -> ok end, DispatcherSpecs),
    {ok, #state{specs = DispatcherSpecs}}.


%%
%%  Convenience function, equivalent to `new(DispatcherSpecs, [])`.
%%
-spec new(
        DispatcherSpecs :: [dispatcher_spec()]
    ) ->
        {ok, Dispatcher :: term()}.

new(DispatcherSpecs) ->
    new(DispatcherSpecs, []).


%%
%%  Send an event via the router.
%%
-spec dispatch(
        Dispatcher  :: term(),
        Event       :: term()
    ) ->
        noreply |
        {reply, Reply :: term()} |
        {error, unknown}.

dispatch(#state{specs = DispatcherSpecs}, Event) ->
    perform_dispatch(DispatcherSpecs, Event).



%% =============================================================================
%%  Internal functions.
%% =============================================================================

%%
%%  Try to send the event using registered callback modules.
%%
perform_dispatch([], _Event) ->
    {error, unknown};

perform_dispatch([{Module, Args} | OtherSpecs], Event) ->
    case Module:handle_dispatch(Event, Args) of
        noreply         -> noreply;
        {reply, Reply}  -> {reply, Reply};
        {error, Reason} -> {error, Reason};
        unknown         -> perform_dispatch(OtherSpecs, Event)
    end.


