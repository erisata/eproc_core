%/--------------------------------------------------------------------
%| Copyright 2013-2014 Robus, Ltd.
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
-module(eproc_fsm_tests).
-compile([{parse_transform, lager_transform}]).
-include_lib("eunit/include/eunit.hrl").

%%
%%
%%
fsm_test() ->
    %Event = a,
    %Store = undefined,
    %Registry = undefined,
    %{ok, InstanceId, ProcessId} = eproc_fsm_void:start_link(Event, Store, Registry),
    %TODO: Asserts
    ok.

%%
%% test for eproc_fsm:create(Module, Args, Options)
%% todo: description
create_test() ->
    % initialization
    application:load(eproc_core),
    application:set_env(eproc_core, store, {eproc_store_ets, []}),
    application:set_env(eproc_core, registry, {eproc_registry_gproc, []}),
    application:ensure_all_started(eproc_core),
    %
    % startup
    {ok, {inst, _} = VoidIID} = eproc_fsm:create(eproc_fsm__void, {}, []),
    {ok, {inst, _} = SeqIID}  = eproc_fsm:create(eproc_fsm__seq,  {}, []),
    %  TODO: Assert the following:
    %   * Instance created.
    %   * Instance is in running strate.
    %   * Instance group assigned properly (new and existing group).
    %   * Instance name assigned properly (with and without name).
    %   * init/1 is invoked.
    %   * Initial state is stored properly.
    %   * Custom options are stored with the instance.
    %
    ok.

%%
%%  Check if start_link/2-3 works.
%%
start_link_test() ->
    application:load(eproc_core),
    application:set_env(eproc_core, store, {eproc_store_ets, []}),
    application:set_env(eproc_core, registry, {eproc_registry_gproc, []}),
    application:ensure_all_started(eproc_core),
    {ok, IID} = eproc_fsm:create(eproc_fsm__void, {}, []),
    {ok, PID} = eproc_fsm:start_link(IID, []),
    % TODO: Assert the following
    %   * Start by IID,
    %   * Start by Name
    %   * Start new instance.
    %       - Check StateData and StateName.
    %   * Restart existing instance.
    %       - Check StateData and StateName.
    %   * Start with FsmName specified.
    %   * Start with restart_delay option.
    %   * Start with all cases of register option.
    %   * Check if callback init/2 is invoked.
    %   * Check initialization of runtime state in init/2.
    %   * Check if callback code_change/3 is invoked with `state`.
    %   * Check if functions id/0, group/0, name/0 work.
    ok.

