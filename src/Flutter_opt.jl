module Flutter_opt

using StaticArrays, NLsolve, NLopt
const I=1im
"""
    fourier_diff(N::Integer)

Construct a Fourier differentiation matrix over [0, 2π] with 2π/N grid spacing.
Since it is a Fourier matrix only N points are used rather than N+1 since the
first and the last points are the same.

See https://people.maths.ox.ac.uk/trefethen/7all.pdf section 7.3 for more
details.
"""
function fourier_diff(N::Integer)
    # For a MATLAB equivalent see http://appliedmaths.sun.ac.za/~weideman/research/differ.html
    h = 2π/N
    D = zeros(N, N)
    # First column
    n = ceil(Int, (N-1)/2)
    if (N % 2) == 0
        for i in 1:n
            D[i+1, 1] = -((i % 2) - 0.5)*cot(i*h/2)
        end
    else
        for i in 1:n
            D[i+1, 1] = -((i % 2) - 0.5)*csc(i*h/2)
        end
    end
    for i in n+2:N
        D[i, 1] = -D[N-i+2, 1]
    end
    # Other columns (circulant matrix)
    for j in 2:N
        D[1, j] = D[N, j-1]
        for i in 2:N
            D[i, j] = D[i-1, j-1]
        end
    end
    return D
end

function flutter_eq(u, p, t) #Flutter equation of motion for Model 1
    ka2=p.ka2
    ka3=p.ka3
    U=p.U

    h           = u[1]
    h_dot       = u[2]
    theta       = u[3]
    theta_dot   = u[4]
    x_bar       = u[5]
    x_bar_dot   = u[6]

    h_ddot=- 210.579*h - 1.0*theta*(0.0338518*U^2 - 3.6782) - theta_dot*(0.00928785*U - 0.0382505) - 0.00308051*U^3*x_bar - 0.00731249*U^2*x_bar_dot - 1.0*h_dot*(0.0338518*U + 0.869643)
    theta_ddot=239.889*h + 0.00350927*U^3*x_bar + 0.00833028*U^2*x_bar_dot - 1.0*theta_dot*(0.0631717*U + 3.29485) - 1.0*ka2*theta^2 - 1.0*ka3*theta^3 + h_dot*(0.0385635*U + 0.990685) + theta*(0.0385635*U^2 - 316.836)
    x_bar_ddot=6.66667*h_dot + theta_dot + 6.66667*U*theta - 2.30333*U*x_bar_dot - 0.606667*U^2*x_bar
    # SVector is much faster for small ODEs (i.e., below 50-100 dimensions)
    return SVector(h_dot,h_ddot,theta_dot,theta_ddot,x_bar_dot,x_bar_ddot)
end

function flutter_eq2(u, p, t) # Flutter equation of motion for Model 2
    ka2=p.ka2
    ka3=p.ka3
    U=p.U

    h           = u[1]
    h_dot       = u[2]
    theta       = u[3]
    theta_dot   = u[4]
    x_bar       = u[5]
    x_bar_dot   = u[6]

    h_ddot=- 197.827*h - 1.0*theta*(0.0338296*U^2 - 3.99137) - theta_dot*(0.00930375*U - 0.0684405) - 0.00307849*U^3*x_bar - 0.0073077*U^2*x_bar_dot - 1.0*h_dot*(0.0338296*U + 0.92079)
    theta_ddot=219.648*h + h_dot*(0.0375611*U + 1.02236) - 1.0*theta_dot*(0.0633343*U + 6.04153) + 0.00341806*U^3*x_bar + 0.00811375*U^2*x_bar_dot - 1.0*ka2*theta^2 - 1.0*ka3*theta^3 + theta*(0.0375611*U^2 - 352.336)
    x_bar_ddot=6.66667*h_dot + theta_dot + 6.66667*U*theta - 2.30333*U*x_bar_dot - 0.606667*U^2*x_bar

    # SVector is much faster for small ODEs (i.e., below 50-100 dimensions)
    return SVector(h_dot,h_ddot,theta_dot,theta_ddot,x_bar_dot,x_bar_ddot)
end

dimension(::typeof(flutter_eq)) = 6
dimension(::typeof(flutter_eq2)) = 6

"""
    periodic_zero_problem!(res, rhs, u, p)

Construct the collocation equations for a periodic boundary value problem using
Fourier collocation. The residual is stored in `res`. It assumes that the
solution is represented on an equispaced grid and that the last point in the
period is omitted (since it is periodic).

The parameter variable, `p`, should contain a field called `D` that contains the
Fourier differentiation matrix of the appropriate size.
"""

function periodic_zero_problem!(res, rhs, u, p)
    # Assume that u has dimensions nN + 1 where n is the dimension of the ODE
    n = dimension(rhs)
    N = (length(u)-1)÷n
    T = u[end]/(2π)  # the differentiation matrix is defined on [0, 2π]
    # Evaluate the right-hand side of the ODE
    for i in 1:n:n*N
        res[i:i+n-1] = T*rhs(@view(u[i:i+n-1]), p, 0)  # use a view for speed
    end
    # Evaluate the derivative; for-loop for speed equivalent to u*Dᵀ
    for (i, ii) in pairs(1:n:n*N)
        # Evaluate the derivative at the i-th grid point
        for (j, jj) in pairs(1:n:n*N)
            for k = 1:n
                res[ii+k-1] -= p.D[i, j]*u[jj+k-1]
            end
        end
    end
    res[end] = (u[1] - 1e-3)  # phase condition - assumes that the limit cycle passes through the Poincare section u₁=1e-4; using a non-zero value prevents convergence to the trivial solution
    return res
end

function Flutter_solve(N,p) # Model 1
# Flutter_solve is function that solves periodic boundary value problem of flutter with using normal form as an initial guess

    ω = 15.4793
    ini_T=2π/ω
    t = range(0, ini_T, length=N+1)[1:end-1]
    eig=[0.0155 - 0.0160*I;0.2474 + 0.2400*I;-0.0000 - 0.0597*I;0.9248 + 0.0000*I;-0.0089 - 0.0034*I;0.0528 - 0.1379*I]
    arg=atan(imag(eig[1])/real(eig[1]))
    eig=exp((-arg+π/2)*1im)*eig
    R2=-0.00879561737287862*(p.U-17.9602)/(-7.10626449516451e-06*p.ka3 + 2.33467790333688e-08*p.ka2^2)
    R=sqrt(R2)
    u1=2*real([R*eig[1]*exp.(I*ω*t)';R*eig[2]*exp.(I*ω*t)';R*eig[3]*exp.(I*ω*t)';R*eig[4]*exp.(I*ω*t)';R*eig[5]*exp.(I*ω*t)';R*eig[6]*exp.(I*ω*t)'])
    # Solve the nonlinear zero problem
    sol = nlsolve((res, u) -> periodic_zero_problem!(res, flutter_eq, u, p), [vec(u1); ini_T])
    return (u=sol.zero, T=sol.zero[end], converged=converged(sol))
end

function Flutter_solve2(N,p) # Model 2
# Flutter_solve is function that solves periodic boundary value problem of flutter with using normal form as an initial guess (model2)

    ω = 15.1829
    ini_T=2π/ω
    t = range(0, ini_T, length=N+1)[1:end-1]
    eig=[ 0.0251 + 0.0251*I   0.3809 - 0.3808*I  -0.0000 + 0.0547*I    0.8304 + 0.0000*I   -0.0067 + 0.0050*I    0.0753 + 0.1017*I];
    arg=atan(imag(eig[1])/real(eig[1]))
    eig=exp((-arg+π/2)*1im)*eig
    R2=-0.6792509995e-2*(p.U-23.95)/(1.282397242*10^(-8)*p.ka2^2-4.610449913*10^(-6)*p.ka3);
    R=sqrt(R2)
    u1=2*real([R*eig[1]*exp.(I*ω*t)';R*eig[2]*exp.(I*ω*t)';R*eig[3]*exp.(I*ω*t)';R*eig[4]*exp.(I*ω*t)';R*eig[5]*exp.(I*ω*t)';R*eig[6]*exp.(I*ω*t)'])
    # Solve the nonlinear zero problem
    sol = nlsolve((res, u) -> periodic_zero_problem!(res, flutter_eq2, u, p), [vec(u1); ini_T])
    return (u=sol.zero, T=sol.zero[end], converged=converged(sol))
end

function Flutter_solve!(N,p,u0) # Model 1
# Flutter_solve! function is function to solve boundary value problem with initial guess u0
    sol = nlsolve((res, u) -> periodic_zero_problem!(res, flutter_eq, u, p), u0)
    return (u=sol.zero, T=sol.zero[end], converged=converged(sol))
end

function Flutter_solve2!(N,p,u0) # Model 2
# Flutter_solve! function is function to solve boundary value problem with initial guess u0
    sol = nlsolve((res, u) -> periodic_zero_problem!(res, flutter_eq2, u, p), u0)
    return (u=sol.zero, T=sol.zero[end], converged=converged(sol))
end

function continuation(N,cp,p0,dU) # Model 1
# Continuation gives continuation result of flutter equation using normal form as an initial guess
    U=Vector{Float64}(undef,cp)
    u=Vector{Vector{Float64}}(undef,cp)
    T=Vector{Float64}(undef,cp)
    s1=Flutter_solve(N,p0)
    DN=fourier_diff(N)

    U[1]=p0.U
    u[1]=s1.u
    T[1]=s1.T
    i=2
    while i<=cp
        U[i]=U[i-1]-dU
        #p.U=U[i]
        p=(ka2=p0.ka2,ka3=p0.ka3,U=U[i],D=DN)

        s2=Flutter_solve!(N,p,u[i-1])
        if s2.converged==true
            u[i]=s2.u
            T[i]=s2.T
            i=i+1
            dU=dU*1.2
        else
            dU=dU/1.2
        end
    end
    return (u=u,U=U,T=T)
end

function continuation2(N,cp,p0,dU) # Model 2
# Continuation gives continuation result of flutter equation using normal form as an initial guess
    U=Vector{Float64}(undef,cp)
    u=Vector{Vector{Float64}}(undef,cp)
    T=Vector{Float64}(undef,cp)
    s1=Flutter_solve2(N,p0)
    DN=fourier_diff(N)

    U[1]=p0.U
    u[1]=s1.u
    T[1]=s1.T
    i=2
    while i<=cp
        U[i]=U[i-1]-dU
        #p.U=U[i]
        p=(ka2=p0.ka2,ka3=p0.ka3,U=U[i],D=DN)

        s2=Flutter_solve2!(N,p,u[i-1])
        if s2.converged==true
            u[i]=s2.u
            T[i]=s2.T
            i=i+1
            dU=dU*1.2
        else
            dU=dU/1.2
        end
    end
    return (u=u,U=U,T=T)
end

function measure_error(ka20::Real,ka30::Real) # Computing the numerical prediction error (Model1)
# measure_error function gives the error=[numerical_amplitude-measured_amplitude] at 2 measured wind speeds
hh=Vector{Float64}(undef,2)
us=Vector{Float64}(undef,2)
mh=Vector{Float64}(undef,2)
ah=Vector{Float64}(undef,20)
# Measuremen results
us[1]=17.2
us[2]=16.5

mh[1]=0.0078
mh[2]=0.0109

N=15
p = (ka2=ka20,ka3=ka30,U=17.9,D=fourier_diff(N))
cp=15
s=continuation(N,cp,p,0.05)

for i in 1:cp
ah[i]=(maximum(s.u[i][1:6:end-1])-minimum(s.u[i][1:6:end-1]))/2
ah[i]=ah[i]^2
end
## interpolate the amplitude of LCO at the measured wind speeds. Note that square amplitude of LCO is proportional to wind speed near the Hopf point.
for i in 1:cp-1
    for j in 1:2
        if us[j]<s.U[i] && s.U[i+1]< us[j]
            au=us[j]-s.U[i]
            bu=s.U[i+1]-us[j]
            c=ah[i+1]-ah[i]
            d=ah[i]+bu*c/(au+bu)
            hh[j]=abs(sqrt(d)-mh[j])
        end
    end
end
e=0
for i in 1:2
e+=hh[i]
end
return e*1000 # Scale of measured error is mm
end

function measure_error2(ka20::Real,ka30::Real) # Computing the numerical prediction error (Model2)
# measure_error function gives the error=[numerical_amplitude-measured_amplitude] at 2 measured wind speeds
hh=Vector{Float64}(undef,4)
us=Vector{Float64}(undef,4)
mh=Vector{Float64}(undef,4)
ah=Vector{Float64}(undef,20)
# Measuremen results
us[1]=23.5
us[2]=22.75
us[3]=21.8
us[4]=21.0

mh[1]=0.007727
mh[2]=0.0148
mh[3]=0.0224
mh[4]=0.02575

N=15
p = (ka2=ka20,ka3=ka30,U=23.9,D=fourier_diff(N))
cp=15
s=continuation2(N,cp,p,0.05)

for i in 1:cp
ah[i]=(maximum(s.u[i][1:6:end-1])-minimum(s.u[i][1:6:end-1]))/2
ah[i]=ah[i]^2
end
## interpolate the amplitude of LCO at the measured wind speeds. Note that square amplitude of LCO is proportional to wind speed near the Hopf point.
for i in 1:cp-1
    for j in 1:4
        if us[j]<s.U[i] && s.U[i+1]< us[j]
            au=us[j]-s.U[i]
            bu=s.U[i+1]-us[j]
            c=ah[i+1]-ah[i]
            d=ah[i]+bu*c/(au+bu)
            hh[j]=abs(sqrt(d)-mh[j])
        end
    end
end
e=0
for i in 1:4
e+=hh[i]
end
return e*1000 # Scale of measured error is mm
end


function my_fun(x::Vector,grad::Vector) # Function to minimize (Model 1)
a=1000*x[1]
b=1000*x[2]

if length(grad)>0
h=0.001
grad[1]=(measure_error(a+h,b)-measure_error(a,b))/h
grad[2]=(measure_error(a,b+h)-measure_error(a,b))/h
end
d=(measure_error(a,b))
return d
end

function my_fun2(x::Vector,grad::Vector) # Function to minimize (Model 2)
a=1000*x[1]
b=1000*x[2]

if length(grad)>0
h=0.001
grad[1]=(measure_error2(a+h,b)-measure_error2(a,b))/h
grad[2]=(measure_error2(a,b+h)-measure_error2(a,b))/h
end
d=(measure_error2(a,b))
return d
end


function my_con(x::Vector,grad::Vector) # Constraint of the optimization (Model 1)
    if length(grad) > 0
    grad[1] = -2*2.33467790333688e-08 *(x[1]*1000)
    grad[2] = 7.10626449516451e-03
end
-((-7.10626449516451e-06*(x[2]*1000)) + 2.33467790333688e-08*(x[1]*1000)^2)
end

function my_con2(x::Vector,grad::Vector) # Constraint of the optimization (Model 2)
    if length(grad) > 0
    grad[1] = -2*8.159808337*10^(-9) *(x[1]*1000)
    grad[2] = 2.703488177e-03
end
-(8.159808337*10^(-9)*(x[1]*1000)^2-2.703488177*10^(-6)*(x[2]*1000))
end

#Optimization using NLopt package
function optimize_NLstiff(x1,x2) # Model 1
    opt = Opt(:LD_MMA, 2)
    opt.lower_bounds = [1, 1]
    opt.upper_bounds = [6, 6]
    opt.xtol_abs = 1e-2
    opt.min_objective = my_fun
    inequality_constraint!(opt, (x,g) -> my_con(x,g), 1e-3)
    (minf,minx,ret) = optimize(opt, [x1, x2])
    return minx
end

function optimize_NLstiff2(x1,x2) # Model 2
    opt = Opt(:LD_MMA, 2)
    opt.lower_bounds = [0.2, 0.2]
    opt.upper_bounds = [6, 6]
    opt.xtol_abs = 1e-2
    opt.min_objective = my_fun2
    inequality_constraint!(opt, (x,g) -> my_con2(x,g), 1e-3)
    (minf,minx,ret) = optimize(opt, [x1, x2])
    return minx
end

end #modlue
