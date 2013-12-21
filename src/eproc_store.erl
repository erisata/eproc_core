%/--------------------------------------------------------------------
%| Copyright 2013 Robus, Ltd.
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
%%  Main interface for a store implementation. The core engine is always using
%%  this module to access the database. Several implementations of this interface
%%  are provided. The `eproc_core` provides ETS and Mnesia based implementations.
%%  Riak based implementation is provided by the `eproc_riak` component.
%%
-module(eproc_store).
-compile([{parse_transform, lager_transform}]).
-export([ref/0, ref/2]).
-export([add_instance/2, load_instance/2]).
-export_type([ref/0]).
-include("eproc.hrl").
-include("eproc_internal.hrl").

-opaque ref() :: {Callback :: module(), Args :: term()}.


%% =============================================================================
%%  Callback definitions.
%% =============================================================================

-callback add_instance(
        StoreArgs   :: term(),
        Instance    :: #instance{}
    ) ->
        {ok, inst_id()}.


-callback load_instance(
        StoreArgs   :: term(),
        InstId      :: inst_id()
    ) ->
        {ok, #instance{}} |
        {error, not_found}.



%% =============================================================================
%%  Public API.
%% =============================================================================


%%
%%  Returns the default store reference.
%%
-spec ref() -> {ok, store_ref()}.

ref() ->
    {ok, {StoreMod, StoreArgs}} = application:get_env(?APP, store),
    ref(StoreMod, StoreArgs).



%%
%%  Create a store reference.
%%
-spec ref(module(), term()) -> {ok, store_ref()}.

ref(Module, Args) ->
    {ok, {Module, Args}}.


%%
%%  Stores new persistent instance, generates id for it,
%%  assigns a group and a name if not provided.
%%
add_instance(StoreRef, Instance) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(StoreRef),
    StoreMod:add_instance(StoreArgs, Instance).


%%
%%  Loads an instance and its current state.
%%  This function returns an instance with single (or zero) transitions.
%%  The transition, if returned, stands for the current state of the FSM.
%%  The transition is also filled with the active props, keys and timers.
%%
load_instance(StoreRef, InstId) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(StoreRef),
    StoreMod:load_instance(StoreArgs, InstId).



%% =============================================================================
%%  Internal functions.
%% =============================================================================

%%
%%  Resolve the provided (optional) store reference.
%%
resolve_ref({StoreMod, StoreArgs}) ->
    {ok, {StoreMod, StoreArgs}};

resolve_ref(undefined) ->
    ref().


