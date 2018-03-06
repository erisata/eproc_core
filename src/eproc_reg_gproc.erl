%/--------------------------------------------------------------------
%| Copyright 2013-2018 Erisata, UAB (Ltd.)
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

%%% @doc
%%% GProc based registry. This registry is not dedesigned to work
%%% in clusters. It can be used for tests or single node deploymens.
%%%
-module(eproc_reg_gproc).
-behaviour(eproc_registry).
-behaviour(gen_server).
-compile([{parse_transform, lager_transform}]).
-export([start_link/2, ref/0, ref/1, load/0, reset/0]).
-export([supervisor_child_specs/1, register_fsm/3, wait_for/3]).
-export([register_name/2, unregister_name/1, whereis_name/1, send/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-include("eproc.hrl").

-define(SUP,     'eproc_reg_gproc$sup').
-define(SUP_DEF, 'eproc_reg_gproc$sup_def').
-define(SUP_MFA, 'eproc_reg_gproc$sup_mfa').
-define(MANAGER, 'eproc_reg_gproc$manager').

-define(BY_INST(I), {n, l, {eproc_inst, I}}).
-define(BY_NAME(N), {n, l, {eproc_name, N}}).


%%% ============================================================================
%%% Public API.
%%% ============================================================================

%%  @doc
%%  Start the registry.
%%
start_link(Name, Load) ->
    gen_server:start_link(Name, ?MODULE, {Load}, []).


%%  @doc
%%  Create reference to this registry.
%%
ref() ->
    eproc_registry:ref(?MODULE, []).


%%  @doc
%%  Create reference to this registry.
%%
ref(Args) ->
    eproc_registry:ref(?MODULE, Args).


%%  @doc
%%  Load FSM instances.
%%
load() ->
    gen_server:cast(?MANAGER, 'eproc_reg_gproc$load').


%%
%%  Reset the registry to its initial state. The loaded FSMs
%%  will be stopped. The reset is implemented by restarting
%%  the registry.
%%
%%  This function can be used when the current node becomes
%%  a secondary node after being a primary node in a hot-stand-by
%%  cluster.
%%
-spec reset() -> ok.

reset() ->
    lager:info("Reseting the registry."),
    eproc_reg_gproc_sup:reset(?SUP).



%%% ============================================================================
%%% Callbacks for `eproc_registry'.
%%% ============================================================================

%%
%%  Returns supervisor child specifications for starting the registry.
%%
supervisor_child_specs(RegistryArgs) ->
    Spec = {eproc_reg_gproc,
        {eproc_reg_gproc_sup, start_link, [RegistryArgs, ?SUP, ?SUP_DEF, ?SUP_MFA, ?MANAGER]},
        permanent, 10000, supervisor, [eproc_reg_gproc_sup]
    },
    {ok, [Spec]}.


%%
%%  Registers FSM with its InstId.
%%
register_fsm(_RegistryArgs, _InstId, Refs) ->
    Register = fun (Ref) ->
        true = gproc:reg(gproc_key(Ref))
    end,
    ok = lists:foreach(Register, Refs).


%%
%%  This function allows to synchronize with the registry. This
%%  function blocks untill the specified event or a timeout occurs.
%%
%%  TODO: This implementation is not sufficient, because there is a
%%  gap between the time, when all the processes are started, and
%%  when all of them have their keys registered. It looks like we
%%  need to wait for all the processes, but now we cannot determine
%%  which processes to wait for.
%%
wait_for(_RegistryArgs, all_started, Timeout) ->
    gen_server:call(?MANAGER, {wait_for, all_started}, Timeout).



%%% ============================================================================
%%% Callbacks for OTP Process Registry.
%%% ============================================================================

%%
%%  Process registration is not implemented for this registry.
%%
register_name(_Name, _Pid) ->
    erlang:error(not_implemented).


%%
%%  Process unregistration is not implemented for this registry.
%%
unregister_name(_Name) ->
    erlang:error(not_implemented).


%%
%%  Process ID lookup. This is used by generic behaviours.
%%
whereis_name({fsm, _RegistryArgs, FsmRef}) ->
    gproc:whereis_name(gproc_key(FsmRef));

whereis_name({new, _RegistryArgs, FsmRef, StartSpec}) ->
    {ok, Pid} = start_fsm(FsmRef, StartSpec),
    Pid;

whereis_name(_UnknownRefType) ->
    undefined.


%%
%%  Sends a message to the specified process.
%%
send(Pid, Message) when is_pid(Pid) ->
    Pid ! Message;

send({fsm, _RegistryArgs, FsmRef}, Message) ->
    gproc:send(gproc_key(FsmRef), Message);

send({new, _RegistryArgs, FsmRef, StartSpec}, Message) ->
    {ok, Pid} = start_fsm(FsmRef, StartSpec),
    Pid ! Message.



%%% ============================================================================
%%% Internal state of the module.
%%% ============================================================================

-record(state, {
    loaded  :: boolean()
}).



%%% ============================================================================
%%% Callbacks for `gen_server'.
%%% ============================================================================

%%
%%  Initialization.
%%
init({Load}) ->
    case Load of
        true  -> self() ! 'eproc_reg_gproc$load';
        false -> ok
    end,
    {ok, #state{loaded = false}}.


%%
%%  Syncronous calls.
%%
handle_call({wait_for, all_started}, _From, State) ->
    % This process is blocked while loading all the FSMs, so we
    % can just reply ok here, because the blocking was in the
    % inbox of this process.
    {reply, ok, State};

handle_call(_Message, _From, State) ->
    {reply, undefined, State}.


%%
%%  Asynchronous messages.
%%
handle_cast('eproc_reg_gproc$load', State) ->
    handle_info('eproc_reg_gproc$load', State);

handle_cast(_Message, State) ->
    {noreply, State}.


%%
%%  Loads all FSM instances asynchronously.
%%
handle_info('eproc_reg_gproc$load', State = #state{loaded = Loaded}) ->
    case Loaded of
        true ->
            {noreply, State};
        false ->
            ok = eproc_registry:wait_for_startup(),
            ok = start_all(),
            {noreply, State}
    end.


%%
%%  Invoked when terminating.
%%
terminate(_Reason, _State) ->
    ok.


%%
%%  Invoked in the case of code upgrade.
%%
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.



%%% ============================================================================
%%% Internal functions.
%%% ============================================================================


%%
%%  Converts FSM refs to gproc keys.
%%
gproc_key({inst, InstId}) ->
    ?BY_INST(InstId);

gproc_key({name, Name}) ->
    ?BY_NAME(Name).


%%
%%  Starts new FSM.
%%
start_fsm(FsmRef, StartSpec) ->
    {ok, _Pid} = case eproc_fsm:resolve_start_spec(FsmRef, StartSpec) of
        {start_link_args, Args} -> eproc_fsm_def_sup:start_fsm(?SUP_DEF, Args);
        {start_link_mfa,  MFA}  -> eproc_fsm_mfa_sup:start_fsm(?SUP_MFA, FsmRef, MFA)
    end.


%%
%%  Restarts all running FSMs.
%%
start_all() ->
    PartitionPred = fun (_InstId, _GroupId) ->
        true
    end,
    StartFsmFun = fun ({FsmRef, StartSpec}) ->
        {ok, _Pid} = start_fsm(FsmRef, StartSpec)
    end,
    {ok, Store} = eproc_store:ref(),
    {ok, Fsms} = eproc_store:load_running(Store, PartitionPred),
    ok = lists:foreach(StartFsmFun, Fsms),
    lager:info("Started ~p FSMs.", [length(Fsms)]),
    ok.


