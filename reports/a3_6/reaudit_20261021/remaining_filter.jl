using JuMP,Test
import HiGHS,JSON
const MOI=JuMP.MOI
a=ldexp(1.3046247794859574e-10,-10); b=3.025002202302713e-8
# An exact feasible point exists, independent of any numerical solver status.
x_exact=Rational{BigInt}(b)/Rational{BigInt}(a)
@test Rational{BigInt}(a)*x_exact==Rational{BigInt}(b)
@test 0<a<1e-12
m=Model(HiGHS.Optimizer); @variable(m,x>=0); @variable(m,0<=z<=1,Int)
@constraint(m,a*x>=b); @objective(m,Min,z)
for (k,v) in (("threads",1),("small_matrix_value",1e-12),("mip_feasibility_tolerance",1e-8)); set_optimizer_attribute(m,k,v); end
optimize!(m)
@test termination_status(m)==MOI.INFEASIBLE
open(io->JSON.print(io,Dict("status"=>string(termination_status(m)),"threshold"=>1e-12,"coefficient"=>a,"rhs"=>b,"exact_feasible_x"=>string(x_exact),"scope"=>"constructed threshold limitation; not a registered-case failure"),2),ARGS[1],"w")
