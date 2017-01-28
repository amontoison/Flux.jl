using Base: @get!
using DataFlow: Constant, constant, Context, interpret, Split,
  interpv, ituple, ilambda, iconst, iline, stack, mux
using Flux: imap

# TODO: implement Julia's type promotion rules

node(x::Tuple) = map(node, x)
node(x::mx.SymbolicNode) = x
# node(x::Number) = TensorFlow.constant(Float32(x))

graph(::typeof(tuple), args...) = (args...,)
graph(s::Split, t::Tuple) = t[s.n]
graph(::typeof(*), args...) = mx.dot(reverse(args)...)
graph(::typeof(+), args...) = mx.broadcast_plus(args...)
graph(::typeof(σ), x) = mx.Activation(data = x, act_type = :sigmoid)
graph(::typeof(relu), x) = mx.Activation(data = x, act_type=:relu)
graph(::typeof(tanh), x) = mx.Activation(data = x, act_type=:tanh)
graph(::typeof(flatten), x) = mx.Flatten(data = x)

graph(::typeof(softmax), xs) =
  mx.broadcast_div(exp(xs), mx.Reshape(mx.sum(exp(xs)), shape = (1,1)))

graph(::typeof(cat), dim::Integer, a...) = mx.Concat(a..., dim = dim)
graph(::typeof(vcat), a...) = node(cat, 1, a...)

graph(::Input, x) = x

# graph(vars, c::Conv, x) =
#   mx.Convolution(data = x,
#                  kernel = c.size,
#                  num_filter = c.features,
#                  stride = c.stride)
#
# graph(vars, p::MaxPool, x) =
#   mx.Pooling(data = x,
#              pool_type = :max,
#              kernel = p.size,
#              stride = p.stride)
#
# graph(vars, d::Dense, x) =
#   mx.FullyConnected(data = x,
#                     num_hidden = size(d.W.x, 1),
#                     weight = graph(vars, d.W),
#                     bias = graph(vars, d.b))

function interp{T<:AArray}(ctx, p::Constant{Flux.Param{T}})
  id = gensym()
  ctx[:params][id] = p.value.x
  return mx.Variable(id)
end

interp(ctx, p::Constant) = node(p.value)

function graph(ctx::Context, model, args...)
  node = graph(model, interpv(ctx, args)...)
  # isa(node, Tensor) && (ctx[:stacks][node.op.name] = stack(ctx))
  return node
end

function interp(ctx, model, args...)
  g = Flux.graph(model)
  g == nothing && return graph(ctx, model, args...)
  DataFlow.iscyclic(g) && error("This model has a cycle; try unrolling it first.")
  interpret(ctx, g, interpv(ctx, args)...)
end

function tograph(model, args...)
  ctx = Context(mux(iline, ilambda, ituple, imap, interp),
                params = Dict(), stacks = Dict())
  out = interp(ctx, model, map(constant, args)...)
  return ctx[:params], ctx[:stacks], out
end
