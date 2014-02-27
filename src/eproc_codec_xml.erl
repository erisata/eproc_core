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
%%  Encodes / decodes erlang terms to/from XML using xmerl.
%%
-module(eproc_codec_xml).
-behaviour(eproc_codec).
-export([encode/1, decode/1]).


%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Encode term to XML.
%%
encode(_Term) ->
    % TODO: Implement.
    {error, not_implemented}.


%%
%%  Decode XML to Erlang term.
%%
decode(_Xml) ->
    % TODO: Implement.
    {error, not_implemented}.



%% =============================================================================
%%  Internal functions.
%% =============================================================================

