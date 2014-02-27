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

-module(eproc_codec).
-compile([{parse_transform, lager_transform}]).
-export([ref/2]).
-export([encode/2, decode/2]).
-export_type([ref/0]).
-include("eproc.hrl").

-opaque ref() :: {Callback :: module(), Args :: term()}.


%% =============================================================================
%%  Callback definitions.
%% =============================================================================

-callback encode(
        CodecArgs   :: term(),
        Term        :: term()
    ) ->
        {ok, Encoded :: iolist()} |
        {error, Reason :: term()}.


-callback decode(
        CodecArgs   :: term(),
        Encoded     :: iolist()
    ) ->
        {ok, Term :: term()} |
        {error, Reason :: term()}.


%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Create a codec reference.
%%
-spec ref(module(), term()) -> {ok, codec_ref()}.

ref(Module, Args) ->
    {ok, {Module, Args}}.


%%
%%
%%
encode(Codec, Term) ->
    {ok, {CodecMod, CodecArgs}} = resolve_ref(Codec),
    CodecMod:encode(CodecArgs, Term).


%%
%%
%%
decode(Codec, Encoded) ->
    {ok, {CodecMod, CodecArgs}} = resolve_ref(Codec),
    CodecMod:decode(CodecArgs, Encoded).



%% =============================================================================
%%  Internal functions.
%% =============================================================================


%%
%%  Resolve the provided codec reference.
%%
resolve_ref({CodecMod, CodecArgs}) ->
    {ok, {CodecMod, CodecArgs}}.


