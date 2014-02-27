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
-module(eproc_codec_xml_tests).
-compile([{parse_transform, lager_transform}]).
-include_lib("eunit/include/eunit.hrl").


%%
%%  Test primitive encoding rules.
%%
encode_test() ->
    {ok, Codec}= eproc_codec:ref(eproc_codec_xml, []),
    {ok, Xml1} = eproc_codec:encode(Codec, 1),
    {ok, Xml2} = eproc_codec:encode(Codec, asd),
    {ok, Xml3} = eproc_codec:encode(Codec, "asd"),
    {ok, Xml4} = eproc_codec:encode(Codec, {}),
    {ok, Xml5} = eproc_codec:encode(Codec, []),
    {ok, Xml6} = eproc_codec:encode(Codec, <<"asd">>),
    ?assertEqual("<?xml version=\"1.0\"?><integer>1</integer>", lists:flatten(Xml1)),
    ?assertEqual("<?xml version=\"1.0\"?><atom>asd</atom>", lists:flatten(Xml2)),
    ?assertEqual("<?xml version=\"1.0\"?><string>asd</string>", lists:flatten(Xml3)),
    ?assertEqual("<?xml version=\"1.0\"?><tuple/>", lists:flatten(Xml4)),
    ?assertEqual("<?xml version=\"1.0\"?><list/>", lists:flatten(Xml5)),
    ?assertEqual("<?xml version=\"1.0\"?><binary>asd</binary>", lists:flatten(Xml6)),
    ok.


%%
%%  Test primitive decoding rules.
%%
decode_test() ->
    {ok, 1}         = eproc_codec_xml:decode(<<"<integer>1</integer>">>),
    {ok, asd}       = eproc_codec_xml:decode(<<"<atom>asd</atom>">>),
    {ok, "asd"}     = eproc_codec_xml:decode(<<"<string>asd</string>">>),
    {ok, {}}        = eproc_codec_xml:decode(<<"<tuple></tuple>">>),
    {ok, []}        = eproc_codec_xml:decode(<<"<list></list>">>),
    {ok, <<"asd">>} = eproc_codec_xml:decode(<<"<binary>asd</binary>">>),
    ok.


%%
%%  Test encoding/decoding cycle.
%%
codec_test() ->
    Decoded = {[1, 2, "123"], [{{{ok, 1, "qwe"}, [asd]}}]},
    {ok, Encoded} = eproc_codec_xml:encode(Decoded),
    {ok, Decoded} = eproc_codec_xml:decode(Encoded),
    ok.


