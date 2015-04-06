

# Module eproc_codec #
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

__This module defines the `eproc_codec` behaviour.__
<br></br>
 Required callback functions: `encode/2`, `decode/2`.

<a name="types"></a>

## Data Types ##




### <a name="type-ref">ref()</a> ###


__abstract datatype__: `ref()`

<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#decode-2">decode/2</a></td><td></td></tr><tr><td valign="top"><a href="#encode-2">encode/2</a></td><td></td></tr><tr><td valign="top"><a href="#ref-2">ref/2</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="decode-2"></a>

### decode/2 ###

`decode(Codec, Encoded) -> any()`


<a name="encode-2"></a>

### encode/2 ###

`encode(Codec, Term) -> any()`


<a name="ref-2"></a>

### ref/2 ###


<pre><code>
ref(Module::module(), Args::term()) -&gt; {ok, <a href="#type-codec_ref">codec_ref()</a>}
</code></pre>

<br></br>



