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
%%  Message router is used to locate FSMs by business specific keys
%%  instead of instance ids ir names. The keys can be added to an FSM
%%  at some transition.
%%
%%  An FSM that should be accessed using business specific keys,
%%  should register them by calling function `add_key/2-3`.
%%  Keys are maintained as FSM attributes and can be limited to
%%  particular scope.
%%
-module(eproc_router).
-behaviour(eproc_fsm_attr).
-export([add_key/3, add_key/2]).
-export([lookup/2, lookup/1, lookup_send/3, lookup_send/2, lookup_sync_send/3, lookup_sync_send/2]).
-export([init/2, handle_created/4, handle_updated/5, handle_removed/3, handle_event/4]).
-include("eproc.hrl").

-record(data, {
    key     :: term(),              %%  Key value
    ref     :: undefined | term()   %%  Reference of the synchronously created key.
}).


%% =============================================================================
%%  API for FSM implementations.
%% =============================================================================

%%
%%  Attaches the specified key to the current FSM. The key can be later
%%  used to lookup FSM instance id. This function should be called from
%%  the FSM process, most likely in the FSM callback's `handle_state/3` function.
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
%%  :   should be set to true, if the key should not be registered if it
%%      is already present (active), and is registered by different FSM instance.
%%      This option is only used, if the key is being added synchronously.
%%      The term `{error, exist}` will be returned in such case.
%%
-spec add_key(
        Key     :: term(),
        Scope   :: scope() | next | undefined,
        Opts    :: [sync | uniq]
    ) ->
        ok |
        {error, exist} |
        {error, Reason :: term()}.

add_key(Key, Scope, Opts) ->
    case proplists:get_keys(Opts) -- [sync, uniq] of
        [] ->
            Sync = proplists:get_value(sync, Opts, false),
            TaskResponse = case Sync of
                false -> {ok, undefined};
                true ->
                    {ok, InstId} = eproc_fsm:id(),
                    Uniq = proplists:get_value(uniq, Opts, false),
                    Task = {key_sync, Key, InstId, Uniq},
                    eproc_fsm_attr:task(?MODULE, Task, [])
            end,
            case TaskResponse of
                {ok, SyncRef} ->
                    Name = undefined,
                    Action = {key, Key, SyncRef},
                    ok = eproc_fsm_attr:action(?MODULE, Name, Action, Scope);
                {error, Reason} ->
                    {error, Reason}
            end;
        Unknown ->
            {error, Unknown}
    end.


%%
%%  Convenience function, equivalent to `add_key(Key, Scope, [])`.
%%
-spec add_key(
        Key     :: term(),
        Scope   :: scope() | next | undefined
    ) ->
        ok.

add_key(Key, Scope) ->
    add_key(Key, Scope, []).



%% =============================================================================
%%  API for Router implementations.
%% =============================================================================

%%
%%  Returns instance instance ids (possibly []) by the specified key.
%%
-spec lookup(
        Key     :: term(),
        Opts    :: [{store, store_ref()}]
    ) ->
        {ok, [inst_id()]} |
        {error, Reason :: term()}.

lookup(Key, Opts) ->
    {ok, Store} = resolve_store(Opts),
    {ok, _InstIds} = eproc_fsm_attr:task(?MODULE, {lookup, Key}, [{store, Store}]).


%%
%%  Convenience function, equivalent to `lookup(Key, [])`.
%%
-spec lookup(
        Key     :: term()
    ) ->
        {ok, [inst_id()]} |
        {error, Reason :: term()}.

lookup(Key) ->
    lookup(Key, []).


%%
%%  Lookups instance ids by the specified key and calls the specified
%%  function for each of them. If `uniq=false` was specified when setuping
%%  the router, multicast sent is performed.
%%
-spec lookup_send(
        Key     :: term(),
        Opts    :: [(uniq | {store, store_ref()})],
        Fun     :: fun((fsm_ref()) -> any())
    ) ->
        ok |
        {error, (not_found | multiple | term())}.

lookup_send(Key, Opts, Fun) ->
    {ok, Uniq} = resolve_uniq(Opts),
    case lookup(Key, Opts) of
        {error, Reason} ->
            {error, Reason};
        {ok, InstIds} ->
            case Uniq of
                false ->
                    [ Fun({inst, InstId}) || InstId <- InstIds ],
                    ok;
                true ->
                    case InstIds of
                        [] ->
                            {error, not_found};
                        [InstId] ->
                            Fun({inst, InstId}),
                            ok;
                        _ when is_list(InstIds) ->
                            {error, multiple}
                    end
            end
    end.


%%
%%  Convenience function, equivalent to `lookup_send(Key, [], Fun)`.
%%
-spec lookup_send(
        Key     :: term(),
        Fun     :: fun((fsm_ref()) -> any())
    ) ->
        ok |
        {error, (not_found | multiple | term())}.

lookup_send(Key, Fun) ->
    lookup_send(Key, [], Fun).


%%
%%  Lookups instance ids by the specified key and calls the specified
%%  function for it. This function does not support multicast and the
%%  `uniq` option is not respected by this function.
%%
-spec lookup_sync_send(
        Key     :: term(),
        Opts    :: [{store, store_ref()}],
        Fun     :: fun((fsm_ref()) -> Reply :: term())
    ) ->
        Reply :: term() |
        {error, (not_found | multiple | term())}.

lookup_sync_send(Key, Opts, Fun) ->
    case lookup(Key, Opts) of
        {error, Reason} ->
            {error, Reason};
        {ok, InstIds} ->
            case InstIds of
                [InstId]          -> Fun({inst, InstId});
                []                -> {error, not_found};
                I when is_list(I) -> {error, multiple}
            end
    end.


%%
%%  Convenience function, equivalent to `lookup_sync_send(Key, [], Fun)`.
%%
-spec lookup_sync_send(
        Key     :: term(),
        Fun     :: fun((fsm_ref()) -> Reply :: term())
    ) ->
        Reply :: term() |
        {error, (not_found | multiple | term())}.

lookup_sync_send(Key, Fun) ->
    lookup_sync_send(Key, [], Fun).



%% =============================================================================
%%  Callbacks for `eproc_fsm_attr`.
%% =============================================================================

%%
%%  FSM started.
%%
init(_InstId, ActiveAttrs) ->
    {ok, [ {A, undefined} || A <- ActiveAttrs ]}.


%%
%%  Attribute created.
%%
handle_created(_InstId, _Attribute, {key, Key, SyncRef}, _Scope) ->
    AttrData = #data{key = Key, ref = SyncRef},
    AttrState = undefined,
    {create, AttrData, AttrState, true}.


%%
%%  Keys cannot be updated.
%%
handle_updated(_InstId, _Attribute, _AttrState, {key, _Key}, _Scope) ->
    {error, keys_non_updateable}.


%%
%%  Attributes should never be removed.
%%
handle_removed(_InstId, _Attribute, _AttrState) ->
    {ok, true}.


%%
%%  Events are not used for keywords.
%%
handle_event(_InstId, _Attribute, _AttrState, Event) ->
    throw({unknown_event, Event}).



%% =============================================================================
%%  Internal functions.
%% =============================================================================

%%
%%  Resolve `store` option.
%%
resolve_store(Opts) ->
    case proplists:get_value(store, Opts) of
        undefined -> eproc_store:ref();
        Store     -> {ok, Store}
    end.


%%
%%  Resolve `uniq` option.
%%
resolve_uniq(Opts) ->
    {ok, proplists:get_value(uniq, Opts, true)}.


