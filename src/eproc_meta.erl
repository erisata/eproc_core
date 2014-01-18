%/--------------------------------------------------------------------
%| Copyright 2013-2014 Erisata, Ltd.
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
%%  TODO: Description.
%%
-module(eproc_meta).
-behaviour(eproc_fsm_attr).
-export([add_keyword/2]).
-export([started/1, created/3, updated/2, removed/1]).


%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%
%%
add_keyword(Value, Type) ->
    eproc_fsm_attr:action(?MODULE, undefined, {keyword, Value, Type}, []).



%% =============================================================================
%%  Callbacks for `eproc_fsm_attr`.
%% =============================================================================

%%
%%  FSM started.
%%
started(ActiveAttrs) ->
    {error, undefined}. % TODO


%%
%%  Attribute created.
%%
created(Name, {keyword, Value, Type}, _Scope) ->
    {error, undefined}. % TODO


%%
%%  Attribute updated by user.
%%
updated(_Attribute, _Action) ->
    {error, undefined}.


%%
%%  Attribute removed by `eproc_fsm`.
%%
removed(_Attribute) ->
    {error, undefined}.



%% =============================================================================
%%  Internal functions.
%% =============================================================================

