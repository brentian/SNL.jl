using ProximalAlgorithms
using DRSOM
using Optim
using LineSearches
using ReverseDiff

function drsom_nls_legacy(n, m, pp, Nx::NeighborVector, Xv::Matrix{Float64}, tol::Float64, max_iter::Real, verbose::Bool)
    function loss(x::AbstractVector{T}) where {T}
        xv = reshape(x, 2, n - m)
        return least_square(n, m, xv, pp, Nx)
    end
    x0 = vec(Xv)
    f_tape = ReverseDiff.GradientTape(loss, x0)
    f_tape_compiled = ReverseDiff.compile(f_tape)
    @printf("compile finished\n")
    iter = DRSOM.DRSOMFreeIteration(x0=x0, rh=DRSOM.hessba, f=loss, tp=f_tape_compiled, mode=:backward)
    rb = nothing
    for (k, state::DRSOM.DRSOMFreeState) in enumerate(iter)

        if k >= max_iter || DRSOM.drsom_stopping_criterion(tol, state)
            rb = state, k
            break
        end
        verbose && mod(k, 1) == 0 && DRSOM.drsom_display(k, state)
    end
    return rb
end

function drsom_nls(n, m, pp, Nx::NeighborVector, Xv::Matrix{Float64}, tol::Float64, max_iter::Real, verbose::Bool, max_time::Real=100.0, freq=10)
    function loss(x::AbstractVector{T}) where {T}
        xv = reshape(x, 2, n - m)
        return least_square(n, m, xv, pp, Nx)
    end
    x0 = vec(Xv)
    g(x) = DRSOM.ReverseDiff.gradient(loss, x)
    r = DRSOM2()(;
        x0=copy(x0), f=loss, g=g,
        verbose=verbose, maxtime=max_time, maxiter=max_iter, tol=tol, freq=freq
    )
    return r.state, r.k
end

function gd_nls(n, m, pp, Nx::NeighborVector, Xv::Matrix{Float64}, tol::Float64, max_iter::Real, verbose::Bool, max_time::Real=100.0, freq=20)
    function loss(x::AbstractVector{T}) where {T}
        xv = reshape(x, 2, n - m)
        return least_square(n, m, xv, pp, Nx)
    end
    x0 = vec(Xv)
    g(x) = DRSOM.ReverseDiff.gradient(loss, x)
    options = Optim.Options(
        g_tol=tol,
        iterations=round(Int, max_iter),
        store_trace=true,
        show_trace=true,
        show_every=freq,
        time_limit=max_time
    )
    res1 = Optim.optimize(
        loss, g, x0,
        GradientDescent(; alphaguess=LineSearches.InitialHagerZhang(),
            linesearch=LineSearches.StrongWolfe()
        ),
        options;
        inplace=false
    )
    return res1, res1
end

function cg_nls(n, m, pp, Nx::NeighborVector, Xv::Matrix{Float64}, tol::Float64, max_iter::Real, verbose::Bool, max_time::Real=100.0, freq=20)
    function loss(x::AbstractVector{T}) where {T}
        xv = reshape(x, 2, n - m)
        return least_square(n, m, xv, pp, Nx)
    end
    x0 = vec(Xv)
    g(x) = DRSOM.ReverseDiff.gradient(loss, x)
    options = Optim.Options(
        g_tol=tol,
        iterations=round(Int, max_iter),
        store_trace=true,
        show_trace=true,
        show_every=freq,
        time_limit=max_time
    )
    res1 = Optim.optimize(
        loss, g, x0,
        ConjugateGradient(;
            alphaguess=LineSearches.InitialStatic(),
            linesearch=LineSearches.HagerZhang()
        ),
        options;
        inplace=false
    )
    return res1, res1
end

function fista_nls(n, m, pp, Nx::NeighborVector, Xv::Matrix{Float64}, tol::Float64, max_iter::Real, verbose::Bool)
    function loss(x::AbstractVector{T}) where {T}
        xv = reshape(x, 2, n - m)
        return least_square(n, m, xv, pp, Nx)
    end
    x0 = vec(Xv)

    iter = ProximalAlgorithms.FastForwardBackwardIteration(x0=x0, f=loss)
    rb = nothing
    for (k, state::ProximalAlgorithms.FastForwardBackwardState) in enumerate(iter)

        if k >= max_iter || ProximalAlgorithms.default_stopping_criterion(tol, iter, state)
            rb = state, k
            break
        end
        verbose && mod(k, 40) == 1 && DRSOM.default_display(k, state.f_x, state.gamma, norm(state.res, Inf))
    end
    return rb
end



include("../third-party/DRSOM.jl/src/utilities/hagerzhang.jl")

function HagerZhangLineSearch(
    f, g,
    gx, fx,
    x::Tx,
    s::Tx,
) where {Tx}

    ??(??) = f(x .+ ?? .* s)
    function d??(??)
        gv = g(x + ?? .* s)
        return dot(gv, s)
    end
    function ??d??(??)
        phi = f(x .+ ?? .* s)
        gv = g(x + ?? .* s)
        dphi = dot(gv, s)
        return (phi, dphi)
    end


    d??_0 = dot(s, gx)
    lsa = HagerZhangEx()
    ??, fx, it = lsa(??, d??, ??d??, 1.0, fx, d??_0)
    return ??, fx, it
end

