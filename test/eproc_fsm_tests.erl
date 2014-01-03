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
-module(eproc_fsm_tests).
-compile([{parse_transform, lager_transform}]).
-include_lib("eunit/include/eunit.hrl").

%%
%%
%%
void_fsm_test() ->
    %Event = a,
    %Store = undefined,
    %Registry = undefined,
    %{ok, InstanceId, ProcessId} = eproc_fsm_void:start_link(Event, Store, Registry),
    %TODO: Asserts
    ok.

%%
%% test for eproc_fsm:create(Module, Args, Options)
%% todo: description
void_fsm_create_test() ->
    % initialization 
    application:load(eproc_core),
    application:set_env(eproc_core, store, {eproc_store_ets, []}),
    application:set_env(eproc_core, registry, {eproc_registry_gproc, []}),
    application:ensure_all_started(eproc_core),
    %
    % startup 
    Module = eproc_fsm_void,
    {ok, InstId} = eproc_fsm:create(Module, {}, []),
    %  todo assert
    %
    ok.
    
    
    