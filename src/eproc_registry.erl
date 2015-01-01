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
%%  Interface module for an FSM instance registry.
%%  The registry is responsible for:
%%
%%   1. Starting all running FSMs on application startup.
%%   2. Starting newly created FSMs on first event send.
%%   3. Supervising all running FSMs.
%%   4. Locating FSMs by an instance id or a name.
%%   5. Send message to an FSM.
%%
%%  Modules implementing this behaviour are also implementing all callbacks needed
%%  for using it as an OTP Process Registry. These callbacks are `register_name/2`,
%%  `unregister_name/1` and `send/2`. I.e. the modules implementing this behaviour
%%  can be used with all the standard OTP behaviours to register and reference
%%  a process using `{via, Module, Name}` as a process name. Only `send/2` callback
%%  is used currently by `eproc_core`.
%%
-module(eproc_registry).
-compile([{parse_transform, lager_transform}]).
-export([supervisor_child_specs/1, ref/0, ref/2]).
-export([make_new_fsm_ref/3, make_fsm_ref/2, register_fsm/3]).
-export_type([ref/0, registry_fsm_ref/0]).
-include("eproc.hrl").

%%
%%  Reference to a registry. I.e. identifies a registry.
%%
-opaque ref() :: {Callback :: module(), Args :: term()}.

%%
%%  Reference to a FSM, handled by this process registry.
%%  This structire is passed to the callbacks defined by the OTP process
%%  registry: `register_name/2`, `unregister_name/1, `send/2`.
%%
-opaque registry_fsm_ref() ::
    {fsm, RegistryArgs :: term(), FsmRef :: fsm_ref()} |
    {new, RegistryArgs :: term(), FsmRef :: fsm_ref(), StartSpec :: fsm_start_spec()}.



%% =============================================================================
%%  Callback definitions.
%% =============================================================================

%%
%%  This callback should return a list of supervisor child specifications
%%  used to start the registry.
%%
-callback supervisor_child_specs(
        RegistryArgs    :: term()
    ) ->
        {ok, list()}.

%%
%%  This callback is used to register FSM with its standard references.
%%  See `register_fsm/3` for more details.
%%
-callback register_fsm(
        RegistryArgs    :: term(),
        InstId          :: inst_id(),
        Refs            :: [fsm_ref()]
    ) ->
        ok.



%% =============================================================================
%%  Callback definitions required by the OTP Process Registry.
%% =============================================================================

%%
%%  This callback is from the OTP Process Registry behaviour.
%%  See `global:register_name/1` for more details.
%%
-callback register_name(
        Name    :: registry_fsm_ref(),
        Pid     :: pid()
    ) ->
        yes | no.

%%
%%  This callback is from the OTP Process Registry behaviour.
%%  See `global:unregister_name/1` for more details.
%%
-callback unregister_name(
        Name    :: registry_fsm_ref()
    ) ->
        ok.

%%
%%  This callback is from the OTP Process Registry behaviour.
%%  See `global:whereis_name/1` for more details.
%%
-callback whereis_name(
        Name    :: registry_fsm_ref()
    ) ->
        Pid :: pid() | undefined.

%%
%%  This callback is from the OTP Process Registry behaviour.
%%  See `global:send/2` for more details.
%%
-callback send(
        Name    :: registry_fsm_ref(),
        Msg     :: term()
    ) ->
        Pid :: pid().



%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Returns supervisor child specifications, that should be used to
%%  start the registry.
%%
-spec supervisor_child_specs(Registry :: registry_ref()) -> {ok, list()}.

supervisor_child_specs(Registry) ->
    {ok, {RegistryMod, RegistryArgs}} = resolve_ref(Registry),
    RegistryMod:supervisor_child_specs(RegistryArgs).


%%
%%  Returns the default registry reference.
%%
-spec ref() -> {ok, registry_ref()} | undefined.

ref() ->
    case eproc_core_app:registry_cfg() of
        {ok, {Module, Function, Args}} ->
            erlang:apply(Module, Function, Args);
        undefined ->
            undefined
    end.


%%
%%  Create a registry reference.
%%
-spec ref(module(), term()) -> {ok, registry_ref()}.

ref(Module, Args) ->
    {ok, {Module, Args}}.


%%
%%  Creates a reference that points to a process, that should be started
%%  prior to sending a message to it. The reference can be passed to any
%%  process as a registry reference (uses `{via, Mudule, Name}`).
%%  I.e. you can use it as:
%%
%%      {ok, Ref} = eproc_registry:make_new_fsm_ref(Registry, FsmRef, StartSpec),
%%      Response = gen_server:call(Ref, Message).
%%
%%  Here registry is a reference obtained using `eproc_registry:ref/1-2`,
%%  FsmRef is an FSM reference, usually returned from the `eproc_fsm:create/3`
%%  and StartSpec tells, how to start and link the FSM.
%%
-spec make_new_fsm_ref(
        Registry    :: registry_ref(),
        FsmRef      :: fsm_ref(),
        StartSpec   :: fsm_start_spec()
    ) ->
        {ok, Ref}
    when
        Ref :: {via, RegistryModule :: module(), RegistryFsmRef :: registry_fsm_ref()}.

make_new_fsm_ref(Registry, FsmRef = {inst, _}, StartSpec) ->
    {ok, {RegistryMod, RegistryArgs}} = resolve_ref(Registry),
    {ok, {via, RegistryMod, {new, RegistryArgs, FsmRef, StartSpec}}}.


%%
%%  Creates a reference that points to an already started FSM.
%%  The reference is in `{via, Mudule, Name}` form so it can
%%  be passed to any process as an OTP process name.
%%
%%  This function is similar to `make_new_fsm_ref/3` except it refers
%%  to an already started process. The later reference a process
%%  that should be started before using it.
%%
-spec make_fsm_ref(
        Registry        :: registry_ref(),
        FsmRef          :: fsm_ref()
    ) ->
        {ok, Ref}
    when
        Ref :: {via, RegistryModule :: module(), RegistryFsmRef :: registry_fsm_ref()}.

make_fsm_ref(Registry, FsmRef) ->
    {ok, {RegistryMod, RegistryArgs}} = resolve_ref(Registry),
    {ok, {via, RegistryMod, {fsm, RegistryArgs, FsmRef}}}.


%%
%%  Register FSM with the specified references. For now those
%%  references can be instance id, instance name or both of them.
%%  This function should be called from the process of the FSM.
%%
-spec register_fsm(
        Registry    :: registry_ref(),
        InstId      :: inst_id(),
        Refs        :: [fsm_ref()]
    ) ->
        ok.

register_fsm(_Registry, _InstId, []) ->
    ok;

register_fsm(Registry, InstId, Refs) ->
    {ok, {RegistryMod, RegistryArgs}} = resolve_ref(Registry),
    RegistryMod:register_fsm(RegistryArgs, InstId, Refs).



%% =============================================================================
%%  Internal functions.
%% =============================================================================

%%
%%  Resolve the provided (optional) registry reference.
%%
resolve_ref({RegistryMod, RegistryArgs}) ->
    {ok, {RegistryMod, RegistryArgs}};

resolve_ref(undefined) ->
    ref().


