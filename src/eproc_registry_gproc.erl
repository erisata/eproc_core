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
%%  GProc based registry.
%%  Can be used for tests or single node deploymens.
%%
-module(eproc_registry_gproc).
-behaviour(eproc_registry).
-compile([{parse_transform, lager_transform}]).
-export([start_link/1]).
-export([
    start_instance/3, await/3,
    register_inst/2, register_name/3, register_keys/3,
    send_event/3
]).
-include("eproc.hrl").

-define(BY_INST(I), {n, l, {eproc_inst, I}}).
-define(BY_NAME(N), {n, l, {eproc_name, N}}).
-define(BY_KEY(K),  {p, l, {eproc_key,  K}}).


%% =============================================================================
%%  Public API.
%% =============================================================================

start_link(_Args) ->
    ignore.


%% TODO: Load all active instances on startup?



%% =============================================================================
%%  Callbacks for `eproc_registry`.
%% =============================================================================

%%
%%  Starts new `eproc_fsm` instance.
%%
start_instance(_RegistryArgs, InstId, StartOpts) ->
    {ok, _PID} = eproc_fsm_sup:start_instance(InstId, StartOpts),   %% TODO: Use this function directly?
    ok.


%%
%%  Awaits for the specified FSM.
%%
await(_RegistryArgs, {inst, InstId}, Timeout) ->
    await(?BY_INST(InstId), Timeout);

await(_RegistryArgs, {name, Name}, Timeout) ->
    await(?BY_NAME(Name), Timeout);

await(_RegistryArgs, {key, Key}, Timeout) ->
    await(?BY_KEY(Key), Timeout).


await(GProcKey, Timeout) ->
    try {_Pid, _Value} = gproc:await(GProcKey, Timeout), ok
    catch error:timeout -> {error, timeout}
    end.


%%
%%  Registers FSM with its InstId.
%%
register_inst(_RegistryArgs, InstId) ->
    true = gproc:reg(?BY_INST(InstId)),
    ok.


%%
%%  Registers FSM with its Name.
%%
register_name(_RegistryArgs, _InstId, Name) ->
    true = gproc:reg(?BY_NAME(Name)),
    ok.


%%
%%  Registers FSM with its Keys.
%%
register_keys(_RegistryArgs, _InstId, Keys) ->
    [ true = gproc:reg(?BY_KEY(Key)) || Key <- Keys ],
    ok.


%%
%%  Sends a message to the specified process.
%%
send_event(_RegistryArgs, {inst, InstId}, Message) ->
    Message = gproc:send(?BY_INST(InstId), Message),
    ok;

send_event(_RegistryArgs, {name, Name}, Message) ->
    Message = gproc:send(?BY_NAME(Name), Message),
    ok;

send_event(_RegistryArgs, {key, Key}, Message) ->
    case gproc:lookup_pids(?BY_KEY(Key)) of
        []    -> {error, not_found};
        [Pid] -> Pid ! Message, ok;
        _     -> {error, multiple}
    end.

