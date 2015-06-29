! Copyright (C) 2014 Santiago Badia, Alberto F. Martín and Javier Principe
!
! This file is part of FEMPAR (Finite Element Multiphysics PARallel library)
!
! FEMPAR is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation, either version 3 of the License, or
! (at your option) any later version.
!
! FEMPAR is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License
! along with FEMPAR. If not, see <http://www.gnu.org/licenses/>.
!
! Additional permission under GNU GPL version 3 section 7
!
! If you modify this Program, or any covered work, by linking or combining it 
! with the Intel Math Kernel Library and/or the Watson Sparse Matrix Package 
! and/or the HSL Mathematical Software Library (or a modified version of them), 
! containing parts covered by the terms of their respective licenses, the
! licensors of this Program grant you additional permission to convey the 
! resulting work. 
!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
module nsi_cg_iss_oss_names
  use types_names
  use memor_names
  use array_names
  use problem_names
  use nsi_names
  use finite_element_names
  use eltrm_gen_names
  use element_fields_names
  use element_tools_names
  use analytical_names
  implicit none
# include "debug.i90"
  
  private
  
  ! INF-SUP STABLE (iss) with Orthogonal SubScales (oss) NAVIER-STOKES types 
  ! Problem data
  type, extends(discrete_problem) :: nsi_cg_iss_oss_discrete_t
     integer(ip) ::   & 
          kfl_thet,   & ! Flag for theta-method (0=BE, 1=CN)
          kfl_lump,   & ! Flag for lumped mass submatrix
          kfl_proj,   & ! Flag for Projections weighted with tau's (On=1, Off=0)
          tdimv,      & ! Number of temporal steps stored for velocity
          tdimp         ! Number of temporal steps stored for pressure   
     real(rp) ::         &
          dtinv,         & ! Inverse of time step
          ctime,         & ! Current time
          ktauc,         & ! Constant multiplying stabilization parameter tau_c 
          k1tau,         & ! C1 constant on stabilization parameter tau_m
          k2tau            ! C2 constant on stabilization parameter tau_m
   contains
     procedure :: create  => nsi_create_discrete
     procedure :: vars_block => nsi_vars_block
     procedure :: dof_coupling => nsi_dof_coupling
  end type nsi_cg_iss_oss_discrete_t

  ! Matvec
  type, extends(discrete_integration) :: nsi_cg_iss_oss_matvec_t
     type(nsi_cg_iss_oss_discrete_t), pointer :: discret
     type(nsi_problem_t)            , pointer :: physics
   contains
     procedure :: create  => nsi_matvec_create
     procedure :: compute => nsi_matvec 
     procedure :: free    => nsi_matvec_free
  end type nsi_cg_iss_oss_matvec_t

!!$  ! Error norm
!!$  type, extends(discrete_integration) :: nsi_cg_iss_oss_error_t
!!$     type(nsi_cg_iss_discrete_t), pointer :: discret
!!$     type(nsi_problem_t)        , pointer :: physics
!!$   contains
!!$     procedure :: create  => nsi_error_create
!!$     procedure :: compute => nsi_error 
!!$     procedure :: free    => nsi_error_free
!!$  end type nsi_cg_iss_oss_error_t

  ! Unkno components parameter definition
  integer(ip), parameter :: current   = 1
  integer(ip), parameter :: prev_iter = 2
  integer(ip), parameter :: prev_step = 3

  ! Types
  public :: nsi_cg_iss_oss_matvec_t, nsi_cg_iss_oss_discrete_t!, nsi_cg_iss_oss_error_t
  
contains

  !=================================================================================================
  subroutine nsi_create_discrete(discret,physics,l2g)
    !----------------------------------------------------------------------------------------------!
    !   This subroutine contains definitions of the Navier-Stokes problem approximed by a stable   !
    !   finite element formulation with inf-sup stable elemets and orthogonal subscales.           !
    !----------------------------------------------------------------------------------------------!
    implicit none
    class(nsi_cg_iss_oss_discrete_t), intent(out) :: discret
    class(physical_problem)         , intent(in)  :: physics
    integer(ip), optional           , intent(in)  :: l2g(:)
    ! Locals
    integer(ip) :: i

    ! Flags
    discret%kfl_lump = 0 ! Flag for lumped mass submatrix (Off=0, On=1)
    discret%kfl_thet = 0 ! Theta-method time integration (BE=0, CN=1)
    discret%kfl_proj = 0 ! Projections weighted with tau's (On=1, Off=0)

    ! Problem variables
    discret%k1tau = 12.0_rp ! C1 constant on stabilization parameter tau_m
    discret%k2tau = 8.0_rp  ! C2 constant on stabilization parameter tau_m
    discret%ktauc = 4.0_rp  ! Constant multiplying stabilization parameter tau_c

    ! Time integration variables
    discret%dtinv = 1.0_rp ! Inverse of time step
    discret%ctime = 0.0_rp ! Current time
    discret%tdimv = 2     ! Number of temporal steps stored for velocity
    discret%tdimp = 2     ! Number of temporal steps stored for pressure

    discret%nvars = 2*physics%ndime+1
    call memalloc(discret%nvars,discret%l2g_var,__FILE__,__LINE__)
    if ( present(l2g) ) then
       assert ( size(l2g) == discret%nvars )
       discret%l2g_var = l2g
    else
       do i = 1,discret%nvars
          discret%l2g_var(i) = i
       end do
    end if
    
  end subroutine nsi_create_discrete 

  !=================================================================================================
  subroutine nsi_matvec_create( approx, physics, discret )
    !----------------------------------------------------------------------------------------------!
    !   This subroutine creates the pointers needed for the discrete integration type              !
    !----------------------------------------------------------------------------------------------!
    implicit none
    class(nsi_cg_iss_oss_matvec_t) , intent(inout) :: approx
    class(physical_problem), target, intent(in)    :: physics
    class(discrete_problem), target, intent(in)    :: discret

    select type (physics)
    type is(nsi_problem_t)
       approx%physics => physics
       class default
       check(.false.)
    end select
    select type (discret)
    type is(nsi_cg_iss_oss_discrete_t)
       approx%discret => discret
       class default
       check(.false.)
    end select

  end subroutine nsi_matvec_create

  !=================================================================================================
  subroutine nsi_matvec_free(approx)
    !----------------------------------------------------------------------------------------------!
    !   This subroutine deallocates the pointers needed for the discrete integration type          !
    !----------------------------------------------------------------------------------------------!
    implicit none
    class(nsi_cg_iss_oss_matvec_t), intent(inout) :: approx

    approx%physics => null()
    approx%discret => null()

  end subroutine nsi_matvec_free

  !=================================================================================================
  subroutine nsi_matvec(approx,finite_element)
    !----------------------------------------------------------------------------------------------!
    !   This subroutine performs the elemental matrix-vector integration selection.                !
    !----------------------------------------------------------------------------------------------!
    implicit none
    class(nsi_cg_iss_oss_matvec_t), intent(inout) :: approx
    type(finite_element_t)        , intent(inout) :: finite_element
    ! Locals
    real(rp), allocatable :: elmat_vu(:,:,:,:)
    real(rp), allocatable :: elmat_vu_diag(:,:)
    real(rp), allocatable :: elmat_vp(:,:,:,:)
    real(rp), allocatable :: elmat_qu(:,:,:,:)
    real(rp), allocatable :: elmat_vx(:,:,:,:)
    real(rp), allocatable :: elmat_wu(:,:,:,:)
    real(rp), allocatable :: elmat_wx(:,:,:,:)
    real(rp), allocatable :: elvec_u(:,:) 
    integer(ip)           :: igaus,idime,inode,jdime,jnode,idof,jdof
    integer(ip)           :: ngaus,ndime,nnodu,nnodp
    real(rp)              :: ctime,dtinv,dvolu,diffu,react
    real(rp)              :: work(4)
    real(rp)              :: agran(finite_element%integ(1)%p%uint_phy%nnode)
    real(rp)              :: tau(2,finite_element%integ(1)%p%quad%ngaus)
    type(vector_t)        :: gpvel, gpveln, force, testf

    ! Checks
    !check(finite_element%reference_element_vars(1)%p%order > finite_element%reference_element_vars(approx%physics%ndime+1)%p%order)
    check(finite_element%integ(1)%p%quad%ngaus == finite_element%integ(approx%physics%ndime+1)%p%quad%ngaus)
    do idime=2,approx%physics%ndime
       check(finite_element%integ(1)%p%uint_phy%nnode == finite_element%integ(idime)%p%uint_phy%nnode)
    end do

    ! Initialize matrix and vector
    finite_element%p_mat%a = 0.0_rp
    finite_element%p_vec%a = 0.0_rp

    ! Unpack variables
    ndime = approx%physics%ndime
    nnodu = finite_element%integ(1)%p%uint_phy%nnode
    nnodp = finite_element%integ(ndime+1)%p%uint_phy%nnode
    ngaus = finite_element%integ(1)%p%quad%ngaus
    diffu = approx%physics%diffu
    react = approx%physics%react
    dtinv = approx%discret%dtinv

    ! Allocate auxiliar matrices and vectors
    call memalloc(ndime,ndime,nnodu,nnodu,elmat_vu,__FILE__,__LINE__)
    call memalloc(nnodu,nnodu,elmat_vu_diag,__FILE__,__LINE__)
    call memalloc(ndime,1,nnodu,nnodp,elmat_vp,__FILE__,__LINE__)
    call memalloc(1,ndime,nnodp,nnodu,elmat_qu,__FILE__,__LINE__)
    call memalloc(ndime,ndime,nnodu,nnodu,elmat_vx,__FILE__,__LINE__)
    call memalloc(ndime,ndime,nnodu,nnodu,elmat_wu,__FILE__,__LINE__)
    call memalloc(ndime,ndime,nnodu,nnodu,elmat_wx,__FILE__,__LINE__)
    call memalloc(ndime,nnodu,elvec_u,__FILE__,__LINE__)

    ! Initialize to zero
    elmat_vu      = 0.0_rp
    elmat_vu_diag = 0.0_rp
    elmat_vp      = 0.0_rp
    elmat_qu      = 0.0_rp
    elmat_vx      = 0.0_rp
    elmat_wu      = 0.0_rp
    elmat_wx      = 0.0_rp
    elvec_u       = 0.0_rp

    ! Interpolation operations for velocity
    call create_vector (approx%physics, 1, finite_element%integ, gpvel)
    call create_vector (approx%physics, 1, finite_element%integ, gpveln)
    call interpolation (finite_element%unkno, 1, prev_iter, finite_element%integ, gpvel)
    gpvel%a=0.0_rp
    if(dtinv == 0.0_rp) then
       call interpolation (finite_element%unkno, 1, prev_step, finite_element%integ, gpveln)
    else
       gpveln%a = 0.0_rp
    end if

    ! Set real time
    if(approx%discret%kfl_thet==0) then        ! BE
       ctime = approx%discret%ctime
    elseif(approx%discret%kfl_thet==1) then    ! CN
       ctime = approx%discret%ctime - 1.0_rp/dtinv
    end if

    ! Set force term
    call create_vector(approx%physics,1,finite_element%integ,force)
    force%a=0.0_rp
    ! Impose analytical solution
    if(approx%physics%case_veloc>0.and.approx%physics%case_press>0) then 
       call nsi_analytical_force(approx%physics,finite_element,ctime,gpvel,force)
    end if

    ! Stabilization parameters
    call create_vector(approx%physics,1,finite_element%integ,testf)
    testf%a = 0.0_rp
    call nsi_elmvsg(approx,finite_element,gpvel%a,tau)
    
    ! Initializations
    work     = 0.0_rp
    agran    = 0.0_rp 

    ! Loop on Gauss points
    do igaus = 1,ngaus
       dvolu = finite_element%integ(1)%p%quad%weight(igaus)*finite_element%integ(1)%p%femap%detjm(igaus)

       ! Auxiliar variables
       if(approx%physics%kfl_conv.ne.0) then
          do inode = 1,nnodu
             agran(inode) = 0.0_rp
             do idime = 1,ndime
                agran(inode) = agran(inode) + &
                     &         gpvel%a(idime,igaus)*finite_element%integ(1)%p%uint_phy%deriv(idime,inode,igaus)
             end do
             testf%a(inode,igaus) = tau(1,igaus)*agran(inode)
          end do
       end if

       ! Add external force term
       do idime=1,approx%physics%ndime    
          force%a(idime,igaus) = force%a(idime,igaus) + approx%physics%gravi(idime)
       end do

       ! Computation of elemental terms
       ! ------------------------------
       ! Block U-V
       ! mu * ( grad u, grad v )
       call elmvis_gal(dvolu,diffu,finite_element%integ(1)%p%uint_phy%deriv(:,:,igaus),ndime,nnodu,elmat_vu_diag, &
            &          work)
       ! Add cross terms for symmetric grad
       if(approx%physics%kfl_symg==1) then
          call elmvis_gal_sym(dvolu,diffu,finite_element%integ(1)%p%uint_phy%deriv(:,:,igaus),ndime,nnodu, &
               &              elmat_vu,work)
       end if
       if(approx%physics%kfl_skew==0) then
          ! (v, a·grad u) + s*(v,u) + (v, u/dt)
          call elmbuv_gal(dvolu,react,dtinv,finite_element%integ(1)%p%uint_phy%shape(:,igaus),agran,nnodu, &
               &          elmat_vu_diag,work)
       elseif(approx%physics%kfl_skew==1) then
          ! 1/2(v, a·grad u) - 1/2(u,a·grad v) + s*(v,u) + (v, u/dt)
          call elmbuv_gal_skew1(dvolu,react,dtinv,finite_element%integ(1)%p%uint_phy%shape(:,igaus),agran,nnodu, &
               &                elmat_vu_diag,work)
       end if
       ! tau*(a·grad u, a·grad v)
       call elmbuv_oss(dvolu,testf%a,agran,nnodu,elmat_vu_diag,work)
       ! tauc*(div v, div u)
       if(approx%discret%ktauc>0.0_rp) then
          call elmdiv_stab(tau(2,igaus),dvolu,finite_element%integ(1)%p%uint_phy%deriv(:,:,igaus),ndime,nnodu, &
               &           elmat_vu,work)
       end if

       ! Block X-V
       ! -tau*(proj(a·grad u), a·grad v)
       if(approx%discret%kfl_proj==1) then
          work(2) = -tau(1,igaus)*dvolu
       else
          work(2) = -dvolu
       end if
       call elmbvu_gal(work(2),finite_element%integ(1)%p%uint_phy%shape(:,igaus),agran,nnodu,elmat_vx, &
            &          work)

       ! Block P-V
       ! - ( div v, p )
       call elmbpv_gal_div_iss(dvolu,finite_element%integ(ndime+1)%p%uint_phy%shape(:,igaus),         &
            &                  finite_element%integ(1)%p%uint_phy%deriv(:,:,igaus),ndime,nnodu,nnodp, &
            &                  elmat_vp,work)

       ! Block U-W
       ! -tau*(proj(a·grad u), a·grad u)
       call elmbuv_gal(-dvolu*tau(1,igaus),0.0_rp,0.0_rp,finite_element%integ(1)%p%uint_phy%shape(:,igaus),agran, &
            &          nnodu,elmat_wu,work)

       ! Block X-W
       ! tau*(proj(a·grad u),v)
       if(approx%discret%kfl_proj==1) then
          call elmmss_gal(dvolu,tau(1,igaus),finite_element%integ(1)%p%uint_phy%shape(:,igaus),nnodu, &
               &          elmat_wx,work)
       else
          call elmmss_gal(dvolu,1.0_rp,finite_element%integ(1)%p%uint_phy%shape(:,igaus),nnodu,elmat_wx, &
               &          work)
       end if
       
       ! Block U-Q
       ! ( div u, q )
       call elmbuq_gal_div_iss(dvolu,finite_element%integ(ndime+1)%p%uint_phy%shape(:,igaus),               &
            &                  finite_element%integ(1)%p%uint_phy%deriv(:,:,igaus),ndime,nnodu,nnodp, &
            &                  elmat_qu,work)

       ! RHS: Block U
       ! ( v, f ) + ( v, u_n/dt )
       call elmrhu_gal(dvolu,dtinv,finite_element%integ(1)%p%uint_phy%shape(:,igaus),gpveln%a(:,igaus), &
            &          force%a(:,igaus),nnodu,ndime,elvec_u,work)

    end do

    call memfree(gpvel%a,__FILE__,__LINE__)
    call memfree(gpveln%a,__FILE__,__LINE__)
    call memfree(force%a,__FILE__,__LINE__)
    call memfree(testf%a,__FILE__,__LINE__)

    ! Assembly to elemental p_mat and p_vec
    do inode=1,nnodu
       do idime=1,ndime
          do jnode=1,nnodu
             do jdime=1,ndime
                ! Block V-U
                idof = finite_element%start%a(idime)+inode-1
                jdof = finite_element%start%a(jdime)+jnode-1
                finite_element%p_mat%a(idof,jdof) =  finite_element%p_mat%a(idof,jdof) + elmat_vu(idime,jdime,inode,jnode)
                ! Block V-X
                jdof = finite_element%start%a(ndime+1+jdime)+jnode-1
                finite_element%p_mat%a(idof,jdof) =  finite_element%p_mat%a(idof,jdof) + elmat_vx(idime,jdime,inode,jnode)
                ! Block W-U
                idof = finite_element%start%a(ndime+1+idime)+inode-1
                jdof = finite_element%start%a(jdime)+jnode-1
                finite_element%p_mat%a(idof,jdof) =  finite_element%p_mat%a(idof,jdof) + elmat_wu(idime,jdime,inode,jnode)
                ! Block W-X
                jdof = finite_element%start%a(ndime+1+jdime)+jnode-1
                finite_element%p_mat%a(idof,jdof) =  finite_element%p_mat%a(idof,jdof) + elmat_wx(idime,jdime,inode,jnode)
             end do    
             ! Block V-U (diag)
             idof = finite_element%start%a(idime)+inode-1
             jdof = finite_element%start%a(idime)+jnode-1
             finite_element%p_mat%a(idof,jdof) = finite_element%p_mat%a(idof,jdof) +  elmat_vu_diag(inode,jnode)
          end do
          do jnode=1,nnodp
             ! Block V-P
             idof = finite_element%start%a(idime)+inode-1
             jdof = finite_element%start%a(ndime+1)+jnode-1
             finite_element%p_mat%a(idof,jdof) = finite_element%p_mat%a(idof,jdof) + elmat_vp(idime,1,inode,jnode)
             ! Block Q-U
             idof = finite_element%start%a(ndime+1)+jnode-1
             jdof = finite_element%start%a(idime)+inode-1
             finite_element%p_mat%a(idof,jdof) = finite_element%p_mat%a(idof,jdof) +  elmat_qu(1,idime,jnode,inode)
          end do
          ! Block U
          idof = finite_element%start%a(idime)+inode-1
          finite_element%p_vec%a(idof) = finite_element%p_vec%a(idof) + elvec_u(idime,inode)
       end do
    end do

    ! Deallocate auxiliar matrices and vectors
    call memfree(elmat_vu,__FILE__,__LINE__)
    call memfree(elmat_vu_diag,__FILE__,__LINE__)
    call memfree(elmat_vp,__FILE__,__LINE__)
    call memfree(elmat_qu,__FILE__,__LINE__)
    call memfree(elmat_vx,__FILE__,__LINE__)
    call memfree(elmat_wu,__FILE__,__LINE__)
    call memfree(elmat_wx,__FILE__,__LINE__)
    call memfree(elvec_u,__FILE__,__LINE__)

    ! Apply boundary conditions
    call impose_strong_dirichlet_data(finite_element) 
    
  end subroutine nsi_matvec

  !==================================================================================================
  subroutine nsi_elmvsg(approx,finite_element,gpvel,tau)
    !----------------------------------------------------------------------------------------------!
    !   This subroutine computes the stabilization parameters.                                     !
    !----------------------------------------------------------------------------------------------!
    !nnode,ndime,approx,hleng,ngaus,jainv,shape,elvel,gpvel,tau,difsma) 
    implicit none
    type(nsi_cg_iss_oss_matvec_t), intent(in)  :: approx
    type(finite_element_t)       , intent(in)  :: finite_element
    real(rp)                     , intent(in)  :: gpvel(approx%physics%ndime,finite_element%integ(1)%p%quad%ngaus)
    real(rp)                     , intent(out) :: tau(2,finite_element%integ(1)%p%quad%ngaus)
    ! Locals
    integer(ip) :: ngaus,ndime,nnodu
    integer(ip) :: igaus,idime
    real(rp)    :: alpha,gpvno,diffu
    real(rp)    :: chave(approx%physics%ndime,2),chale(2)

    ! Unpack variables
    ndime = approx%physics%ndime
    nnodu = finite_element%integ(1)%p%uint_phy%nnode
    ngaus = finite_element%integ(1)%p%quad%ngaus
    diffu = approx%physics%diffu

    ! Initialize
    tau = 0.0_rp

    do igaus=1,ngaus

       ! Velocity norm at gauss point
       gpvno=0.0_rp
       do idime=1,ndime
          gpvno = gpvno + gpvel(idime,igaus)*gpvel(idime,igaus)
       end do
       gpvno = sqrt(gpvno)

       ! Compute the characteristic length chale
       call nsi_elmchl(finite_element%integ(1)%p%femap%jainv,finite_element%integ(1)%p%femap%hleng(:,igaus), &
            &          finite_element%unkno(1:nnodu,1:ndime,1),ndime,nnodu,approx%physics%kfl_conv,chave,chale)
       
       ! Auxiliar computations
       alpha  = approx%discret%k1tau*diffu/(chale(2)*chale(2)) + approx%discret%k2tau*gpvno/chale(1) + &
            &   1.0_rp*approx%physics%react  ! Old
       !alpha  = k1tau*diffu/(chale(2)*chale(2)) + k2tau*facto*gpvno/chale(1) + 1.0_rp*approx%react   ! Codina-Guasch

       ! NS parameters
       if(alpha.gt.1e-8) tau(1,igaus) = 1.0_rp/(alpha)
       if(approx%discret%k1tau.gt.1e-8) then
          tau(2,igaus) = approx%discret%ktauc*(diffu+approx%discret%k2tau/approx%discret%k1tau*gpvno*chale(2))
       end if
    end do

  end subroutine nsi_elmvsg

  !==================================================================================================
  subroutine nsi_vars_block(discret,physics,vars_block)
    !-----------------------------------------------------------------------------------------------!
    !   This subroutine generate the vars per block array needed for dof_handler creation.          !
    !-----------------------------------------------------------------------------------------------!
    implicit none
    class(nsi_cg_iss_oss_discrete_t), intent(in)  :: discret
    type(nsi_problem_t)             , intent(in)  :: physics
    integer(ip), allocatable        , intent(out) :: vars_block(:)
    ! Locals
    integer(ip) :: idime

    call memalloc(discret%nvars,vars_block,__FILE__,__LINE__)

    ! Block U
    do idime=1,physics%ndime
       vars_block(idime) = 1
    end do
    ! Block P
    vars_block(physics%ndime+1) = 2
    ! Block X
    do idime=1,physics%ndime
       vars_block(physics%ndime+1+idime) = 3
    end do

  end subroutine nsi_vars_block

  !==================================================================================================
  subroutine nsi_dof_coupling(discret,physics,dof_coupling)
    !-----------------------------------------------------------------------------------------------!
    !   This subroutine generate the dof coupling array needed for dof_handler creation.            !
    !-----------------------------------------------------------------------------------------------!
    implicit none
    class(nsi_cg_iss_oss_discrete_t), intent(in)  :: discret
    type(nsi_problem_t)             , intent(in)  :: physics
    integer(ip), allocatable        , intent(out) :: dof_coupling(:,:)
    ! Locals
    integer(ip) :: idime,jdime

    call memalloc(discret%nvars,discret%nvars,dof_coupling,__FILE__,__LINE__)
    dof_coupling = 0

    do idime=1,physics%ndime
       do jdime=1,physics%ndime
          ! Block V-U (all)
          dof_coupling(idime,jdime) = 1
          ! Block V-X (all)
          dof_coupling(idime,physics%ndime+1+jdime) = 1
          ! Block W-U (all)
          dof_coupling(physics%ndime+1+idime,jdime) = 1
       end do
       ! Block W-X (diag)
       dof_coupling(physics%ndime+1+idime,physics%ndime+1+idime) = 1
       ! Block V-P
       dof_coupling(idime,physics%ndime+1) = 1
       ! Block Q-U
       dof_coupling(physics%ndime+1,idime) = 1
    end do  
    
  end subroutine nsi_dof_coupling    
  
end module nsi_cg_iss_oss_names
