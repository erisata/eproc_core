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
-module(eproc_fsm_tests).
-compile([{parse_transform, lager_transform}]).
-define(DEBUG, true).
-include_lib("eunit/include/eunit.hrl").
-include("eproc.hrl").



application_setup() ->
    % See config in "test/sys.config" and its use in Makefile.
    %
    % application:set_env(kernel, error_logger, {file, "log/eunit_kernel.log"}),
    % application:set_env(sasl, sasl_error_logger, {file, "log/eunit_sasl.log"}),
    % application:set_env(lager, handlers, [{lager_file_backend, [{file, "log/eunit_lager.log"}, {level, debug}]}]),
    % application:set_env(lager, error_logger_redirect, true),
    %
    application:load(eproc_core),
    application:set_env(eproc_core, store, {eproc_store_ets, []}),
    application:set_env(eproc_core, registry, {eproc_registry_gproc, []}),
    %
    application:ensure_all_started(eproc_core).


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
    ?debugFmt("~n [debug] create_test START. ~n", []),
    % initialization
    application_setup(),
    StoreRef = {eproc_store_ets, []},
    ok = meck:new(eproc_fsm__void, [non_strict, passthrough]),
    ok = meck:expect(eproc_fsm__void, init, 
        fun(Args) -> 
            ?debugFmt("~n [debug] mecked function invoked. [Args=~p] ~n", [Args]),
            meck:passthrough([Args]) 
        end),
    %
    % create test proceses
    {ok, {inst, _} = VoidIID} = eproc_fsm:create(eproc_fsm__void, {}, 
        [{group, abc}, {name, void_test}]),
    %{ok, {inst, _} = SeqIID}  = eproc_fsm:create(eproc_fsm__seq,  {}, []),
    %
    % asserts
    %   * Instance created.
    {ok, Instance} = eproc_store:get_instance(StoreRef, VoidIID, []),
    ?debugFmt("~n [debug] Instance: ~p ~n", [Instance]),
    %   * Instance is in running state.
    ?assertEqual(running, Instance#instance.status),
    %   * Instance group assigned properly (new and existing group).
    ?assertEqual(abc, Instance#instance.group),
    %   * Instance name assigned properly (with and without name).
    ?assertEqual(void_test, Instance#instance.name),
    %
    % TODO
    %   * init/1 is invoked.
    ?assert(meck:validate(eproc_fsm__void)),
%    ok = meck:unload(eproc_fsm__void),
    %
    %   * Initial state is stored properly.
    %% ka reiskia "stored properly"?
    %   * Custom options are stored with the instance.
    %% kas yra "custom options"?
    %
    ok.

%%
%%  Check if start_link/2-3 works.
%%
start_link_test() ->
    application_setup(),
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

