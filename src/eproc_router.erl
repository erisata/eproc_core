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
%%  Message router is used to map incoming messages to FSM events and
%%  to route them to the corresponding FSM instances.
%%
%%  An FSM whos messages should be routed using this router, should
%%  provide keys, that uniquelly identified an FSM instance. Function
%%  `add_key/2` should be used by FSM implementations to attach keys.
%%  Keys are maintained as FSM attributes and can be limited to
%%  particular scope.
%%
-module(eproc_router).
-behaviour(eproc_fsm_attr).
-export([add_key/3, add_key/2]).
-export([lookup/2, lookup_send/3, lookup_sync_send/3, setup/2, send_event/2, sync_send_event/2]).
-export([init/1, handle_created/3, handle_updated/4, handle_removed/2, handle_event/3]).
-include("eproc.hrl").

-record(state, {
    mods    :: [module()],
    store   :: store_ref(),
    uniq    :: boolean()
}).

-record(data, {
    key     :: term(),              %%  Key value
    ref     :: undefined | term()   %%  Reference of the synchronously created key.
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
%%    * Call `eproc_router:lookup/1` to get FSM instance id or ids.
%%    * Call the corresponding FSM implementation.
%%
%%  Example:
%%
%%      handle_event({order_update, OrderNr, NewPrice}, _Args, Router) ->
%%          {ok, [InstId]} = eproc_router:lookup(Router, {order, OrderId}),
%%          ok = my_order:new_price({inst, InstId}, NewPrice),
%%          noreply.
%%
%%      handle_event({order_update, OrderNr, NewPrice}, _Args, Router) ->
%%          eproc_router:lookup_send(Router, {order, OrderId}, fun (FsmRef) ->
%%              ok = my_order:new_price(FsmRef, NewPrice)
%%          end).
%%
%%  This function should return `noreply`, if the call was asynchonous,
%%  `{reply, Reply}` if the call was synchronous, and `unknown` if the
%%  message is not recognized by this callback module.
%%
-callback handle_event(
        Event       :: term(),
        EventType   :: sync | async,
        Args        :: term(),
        Router      :: term()
    ) ->
        noreply |
        {reply, Reply :: term()} |
        {error, Reason :: term()} |
        unknown.



%% =============================================================================
%%  API for FSM implementations.
%% =============================================================================

%%
%%  Attaches the specified key to the current FSM. The key can be later
%%  used to lookup FSM instance id, primarily - in the router's callback
%%  `handle_event/?`. This function should be called from the FSM process,
%%  most likely in the FSM callback's `handle_state/3` function.
%%
%%  The attached key is valid for the specified scope. I.e. the key will
%%  be automatically deactivated, if the FSM will exit the specified scope.
%%
%%  This function can take several options:
%%
%%  `sync`
%%  :   if the key should be added synchronously, i.e. the key should
%%      be available right after this function exits. If this option is
%%      not present, the key will be activated at the end of the transition.
%%      Synchronous key activation is less effective, altrough can be necessary
%%      in the cases, when a call should be made rigth after adding the key and
%%      the key is needed for routing the response of that call.
%%  `uniq`
%%  :   should be set to fail, if the key is already present (active),
%%      and is registered by different FSM instance. This option is only
%%      used, if the key is being added synchronously.
%%
-spec add_key(
        Key     :: term(),
        Scope   :: scope(),
        Opts    :: [sync | uniq]
    ) ->
        ok |
        {error, Reason :: term()}.

add_key(Key, Scope, Opts) ->
    case proplists:get_keys(Opts) -- [sync, uniq] of
        [] ->
            Sync = proplists:get_value(sync, Opts, false),
            {ok, SyncRef} = case Sync of
                false -> {ok, undefined};
                true ->
                    {ok, InstId} = eproc_fsm:id(),
                    Uniq = proplists:get_value(uniq, Opts, false),
                    Task = {key_sync, Key, InstId, Uniq},
                    eproc_fsm_attr:task(?MODULE, Task, [])
            end,
            Name = undefined,
            Action = {key, Key, SyncRef},
            ok = eproc_fsm_attr:action(?MODULE, Name, Action, Scope);
        Unknown ->
            {error, Unknown}
    end.


%%
%%  Simplified version of the `add_key/3`, assumes Opts = [].
%%
-spec add_key(
        Key     :: term(),
        Scope   :: scope()
    ) ->
        ok.

add_key(Key, Scope) ->
    add_key(Key, Scope, []).



%% =============================================================================
%%  API for Router users.
%% =============================================================================

%%
%%  Configute new router. This function is used by router clients.
%%  The Modules parameter takes a list of module/args pairs.
%%  The specified modules should implement `eproc_router` behaviour.
%%
%%  Several options can be provided here:
%%
%%  `uniq`
%%  :   tells, if all lookup functions should expect at most
%%      one instance id when performing lookup. This is true by default.
%%      If `uniq=true`, `lookup/2` will return instance id or error.
%%      If `uniq=false`, this function returns a list of instance ids,
%%      including empty list.
%%  `{store, store_ref()}`
%%  :   if a specific store should be used for key lookups.
%%      This is mainly intended for testing purposes.
%%
-spec setup(
        Modules :: [{Module :: module(), Args :: list()}],
        Opts    :: [(uniq | {store, store_ref()})]
    ) ->
        {ok, Router :: term()}.

setup(Modules, Opts) ->
    lists:foreach(fun ({_M, _A}) -> ok end, Modules),
    Store = proplists:get_value(store, Opts, eproc_store:ref()),
    Uniq  = proplists:get_value(uniq, Opts, true),
    {ok, #state{mods = Modules, store = Store, uniq = Uniq}}.


%%
%%  Send an asynchonous event via the router.
%%
-spec send_event(
        Router  :: term(),
        Event   :: term()
    ) ->
        noreply |
        {error, unknown}.

send_event(Router = #state{mods = Modules}, Event) ->
    dispatch(Modules, Router#state{mods = undefined}, Event, async).


%%
%%  Send a synchronous event via the router.
%%
-spec sync_send_event(
        Router  :: term(),
        Event   :: term()
    ) ->
        {reply, Reply :: term()} |
        {error, unknown}.

sync_send_event(Router = #state{mods = Modules}, Event) ->
    dispatch(Modules, Router#state{mods = undefined}, Event, sync).



%% =============================================================================
%%  API for Router implementations.
%% =============================================================================

%%
%%  Returns instance instance ids (possibly []) by the specified key.
%%
-spec lookup(
        Router  :: term(),
        Key     :: term()
    ) ->
        {ok, [inst_id()]} |
        {error, Reason :: term()}.

lookup(#state{store = Store}, Key) ->
    {ok, _InstIds} = eproc_fsm_attr:task(?MODULE, {lookup, Key}, [{store, Store}]).


%%
%%  Lookups instance ids by the specified key and calls the specified
%%  function for each of them. If `uniq=false` was specified when setuping
%%  the router, multicast sent is performed.
%%
-spec lookup_send(
        Router  :: term(),
        Key     :: term(),
        Fun     :: fun((fsm_ref()) -> any())
    ) ->
        noreply |
        {error, (not_found | multiple | term())}.

lookup_send(Router = #state{uniq = Uniq}, Key, Fun) ->
    case lookup(Router, Key) of
        {error, Reason} ->
            {error, Reason};
        {ok, InstIds} ->
            case Uniq of
                false ->
                    [ Fun({inst, InstId}) || InstId <- InstIds ],
                    noreply;
                true ->
                    case InstIds of
                        [] ->
                            {error, not_found};
                        [InstId] ->
                            Fun({inst, InstId}),
                            noreply;
                        _ when is_list(InstIds) ->
                            {error, multiple}
                    end
            end
    end.


%%
%%  Lookups instance ids by the specified key and calls the specified
%%  function for it. This function does not support multicast and the
%%  `uniq` option is not respected by this function.
%%
-spec lookup_sync_send(
        Router  :: term(),
        Key     :: term(),
        Fun     :: fun((fsm_ref()) -> Reply :: term())
    ) ->
        noreply |
        {error, (not_found | multiple | term())}.

lookup_sync_send(Router, Key, Fun) ->
    case lookup(Router, Key) of
        {error, Reason} ->
            {error, Reason};
        {ok, InstIds} ->
            case InstIds of
                [] ->
                    {error, not_found};
                [InstId] ->
                    Reply = Fun({inst, InstId}),
                    {reply, Reply};
                _ when is_list(InstIds) ->
                    {error, multiple}
            end
    end.



%% =============================================================================
%%  Callbacks for `eproc_fsm_attr`.
%% =============================================================================

%%
%%  FSM started.
%%
init(ActiveAttrs) ->
    {ok, [ {A, undefined} || A <- ActiveAttrs ]}.


%%
%%  Attribute created.
%%
handle_created(_Attribute, {key, Key, SyncRef}, _Scope) ->
    AttrData = #data{key = Key, ref = SyncRef},
    AttrState = undefined,
    {create, AttrData, AttrState, true}.


%%
%%  Keys cannot be updated.
%%
handle_updated(_Attribute, _AttrState, {key, _Key}, _Scope) ->
    {error, keys_non_updateable}.


%%
%%  Attributes should never be removed.
%%
handle_removed(_Attribute, _AttrState) ->
    {ok, true}.


%%
%%  Events are not used for keywords.
%%
handle_event(_Attribute, _AttrState, Event) ->
    throw({unknown_event, Event}).



%% =============================================================================
%%  Internal functions.
%% =============================================================================

%%
%%  Dispatch event using registered callback modules.
%%
dispatch([], _Router, _Event, _Type) ->
    {error, unknown};

dispatch([{Module, Args} | OtherModules], Router, Event, Type) ->
    case Module:handle_event(Event, Type, Args, Router) of
        noreply         -> noreply;
        {reply, Reply}  -> {reply, Reply};
        {error, Reason} -> {error, Reason};
        unknown         -> dispatch(OtherModules, Router, Event, Type)
    end.


