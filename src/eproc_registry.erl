%/--------------------------------------------------------------------
%| Copyright 2013 Karolis Petrauskas
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
%%  Interface module for a registry. The registry is responsible for:
%%
%%   1. Supervising running FSMs.   TODO: Is registry a correct place for the FSM supervisor?
%%   2. Locating FSMs by an instance id, a name or a key.
%%   3. Await for specific FSM.
%%   4. Send message to a FSM.
%%
-module(eproc_registry).
-compile([{parse_transform, lager_transform}]).
-export([
    ref/2, start_instance/3, await/3,
    register_inst/2, register_name/3, register_keys/3,
    send_event/3
]).
-export_type([ref/0]).
-include("eproc.hrl").

-opaque ref() :: {Callback :: module(), Args :: term()}.


%% =============================================================================
%%  Callback definitions.
%% =============================================================================

%%
%%
%%
-callback start_instance(
        RegistryArgs    :: term(),
        InstId          :: inst_id(),
        StartOpts       :: term()
    ) ->
    ok.


%%
%%
%%
-callback await(
        RegistryArgs    :: term(),
        FsmRef          :: fsm_ref(),
        Timeout         :: integer()
    ) ->
    ok | {error, timeout}.


%%
%%
%%
-callback register_inst(
        RegistryArgs    :: term(),
        InstId          :: inst_id()
    ) ->
    ok.


%%
%%
%%
-callback register_name(
        RegistryArgs    :: term(),
        InstId          :: inst_id(),
        Name            :: term()
    ) ->
    ok.


%%
%%
%%
-callback register_keys(
        RegistryArgs    :: term(),
        InstId          :: inst_id(),
        Keys            :: [term()]
    ) ->
    ok.


%%
%%
%%
-callback send_event(
        RegistryArgs    :: term(),
        FsmRef          :: fsm_ref(),
        Message         :: term()
    ) ->
    ok.



%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Create a registry reference.
%%
-spec ref(
        module(),
        term()
        ) ->
        {ok, registry_ref()}.

ref(Module, Args) ->
    {ok, {Module, Args}}.


%%
%%
%%
start_instance(Registry, InstId, StartOpts) ->
    {RegistryMod, RegistryArgs} = resolve_ref(Registry),
    RegistryMod:start_instance(RegistryArgs, InstId, StartOpts).


%%
%%
%%
await(Registry, FsmRef, Timeout) ->
    {RegistryMod, RegistryArgs} = resolve_ref(Registry),
    RegistryMod:await(RegistryArgs, FsmRef, Timeout).


%%
%%
%%
register_inst(Registry, InstId) ->
    {RegistryMod, RegistryArgs} = resolve_ref(Registry),
    RegistryMod:register_inst(RegistryArgs, InstId).


%%
%%
%%
register_name(_Registry, _InstId, undefined) ->
    ok;

register_name(Registry, InstId, Name) ->
    {RegistryMod, RegistryArgs} = resolve_ref(Registry),
    RegistryMod:register_name(RegistryArgs, InstId, Name).


%%
%%
%%
register_keys(_Registry, _InstId, []) ->
    ok;

register_keys(Registry, InstId, Keys) when is_list(Keys) ->
    {RegistryMod, RegistryArgs} = resolve_ref(Registry),
    RegistryMod:register_keys(RegistryArgs, InstId, Keys).


%%
%%
%%
send_event(Registry, FsmRef, Message) ->
    {RegistryMod, RegistryArgs} = resolve_ref(Registry),
    RegistryMod:send_event(RegistryArgs, FsmRef, Message).



%% =============================================================================
%%  Internal functions.
%% =============================================================================

%%
%%  Resolves a registry.
%%
resolve_ref(undefined) ->
    eproc:registry();

resolve_ref(Registry) ->
    Registry.

