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
%%  Mnesia-based EProc store implementation.
%%
-module(eproc_store_mnesia).
-behaviour(eproc_store).
-compile([{parse_transform, lager_transform}]).
-export([add_instance/4]).
-include("eproc.hrl").


%% =============================================================================
%%  Callbacks for `gen_fsm`.
%% =============================================================================

%%
%%
%%
add_instance(_StoreArgs, _FsmModule, _FsmArgs, _FsmGroup) ->
    % TODO: Implement.
    {ok, undefined}.



%% =============================================================================
%%  Internal functions.
%% =============================================================================


