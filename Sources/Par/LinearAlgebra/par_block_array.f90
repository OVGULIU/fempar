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
module par_block_array_names
  ! Serial modules
  use types_names
  use memor_names
  use serial_scalar_array_names
  use array_names
  use vector_names
  
  ! Parallel modules
  use par_environment_names
  use par_scalar_array_names
  use blocks_dof_distribution_names

  implicit none
# include "debug.i90"

  private

  integer(ip), parameter :: not_created  = 0
  integer(ip), parameter :: blocks_container_created = 1
  
  type, extends(array_t) :: par_block_array_t
     integer(ip) :: state = not_created
     integer(ip) :: nblocks = 0
     type(par_scalar_array_t), allocatable :: blocks(:)
   contains	 
     procedure, private :: par_block_array_create_only_blocks_container
     procedure, private :: par_block_array_create_blocks_container_and_blocks
     generic :: create => par_block_array_create_only_blocks_container, & 
                          par_block_array_create_blocks_container_and_blocks
     procedure :: create_and_allocate => par_block_array_create_blocks_container_and_allocate_blocks
     procedure :: allocate => par_block_array_create_blocks_allocate_blocks						  

     procedure :: create_view => par_block_array_create_view
     procedure :: weight => par_block_array_weight
     procedure :: print => par_block_array_print
     procedure :: get_block => par_block_array_get_block
     procedure :: get_nblocks => par_block_array_get_nblocks

     procedure :: dot   => par_block_array_dot
     procedure :: local_dot   => par_block_array_local_dot
     procedure :: copy  => par_block_array_copy
     procedure :: init  => par_block_array_init
     procedure :: scal  => par_block_array_scal
     procedure :: axpby => par_block_array_axpby
     procedure :: nrm2  => par_block_array_nrm2
     procedure :: clone => par_block_array_clone
     procedure :: comm  => par_block_array_comm
     procedure :: same_vector_space => par_block_array_same_vector_space
     procedure :: free_in_stages  => par_block_array_free_in_stages
					procedure :: get_number_blocks
  end type par_block_array_t

  ! Types
  public :: par_block_array_t
  
contains
  !=============================================================================
  subroutine par_block_array_create_only_blocks_container (this, nblocks)
    implicit none
    class(par_block_array_t), intent(out) :: this
    integer(ip)             , intent(in)  :: nblocks

    this%nblocks = nblocks
    allocate ( this%blocks(nblocks) )
    this%state = blocks_container_created
  end subroutine par_block_array_create_only_blocks_container

  !=============================================================================
  subroutine par_block_array_create_blocks_container_and_blocks(this, nblocks, blocks_dof_distribution)
    implicit none
    class(par_block_array_t)      , intent(out) :: this
    integer(ip)                   , intent(in)  :: nblocks
    type(blocks_dof_distribution_t), intent(in) :: blocks_dof_distribution
    integer(ip)  :: ib

    call this%create(nblocks)
    do ib=1, this%nblocks
       call this%blocks(ib)%create ( blocks_dof_distribution%blocks(ib), blocks_dof_distribution%p_env )
    end do
    this%state = blocks_container_created
  end subroutine par_block_array_create_blocks_container_and_blocks
  
  !=============================================================================
  subroutine par_block_array_create_blocks_container_and_allocate_blocks(this, nblocks, blocks_dof_distribution)
    implicit none
    class(par_block_array_t)       , intent(out) :: this
    integer(ip)                    , intent(in)  :: nblocks
    type(blocks_dof_distribution_t), intent(in)  :: blocks_dof_distribution
    integer(ip)  :: ib

    call this%create(nblocks)
    do ib=1, this%nblocks
       call this%blocks(ib)%create_and_allocate ( blocks_dof_distribution%blocks(ib), blocks_dof_distribution%p_env )
    end do
    this%state = blocks_container_created
  end subroutine par_block_array_create_blocks_container_and_allocate_blocks
  
  !=============================================================================
  subroutine par_block_array_create_blocks_allocate_blocks(this)
    implicit none
    class(par_block_array_t), intent(inout) :: this
    integer(ip)  :: ib
    
    assert ( this%state ==  blocks_container_created )
    do ib=1, this%nblocks
       call this%blocks(ib)%allocate ()
    end do
  end subroutine par_block_array_create_blocks_allocate_blocks

  !=============================================================================
  subroutine par_block_array_create_view (this, start, end, tvec)
    implicit none
    ! Parameters
    class(par_block_array_t), intent(in)  :: this
    integer(ip)     , intent(in)        :: start
    integer(ip)     , intent(in)        :: end
    type(par_block_array_t), intent(out) :: tvec

    ! Locals
    integer(ip) :: ib

    call tvec%create(this%nblocks)
    do ib=1, this%nblocks
       call this%blocks(ib)%create_view(start, end, tvec%blocks(ib))
    end do
    tvec%state = blocks_container_created
  end subroutine par_block_array_create_view

  subroutine par_block_array_weight ( p_vec )
    implicit none
    class(par_block_array_t), intent(inout) :: p_vec
    integer(ip) :: ib
    assert(p_vec%state == blocks_container_created)
    do ib=1, p_vec%nblocks
       call p_vec%blocks(ib)%weight()
    end do
  end subroutine par_block_array_weight

  subroutine par_block_array_print (this,luout)
    implicit none
    class(par_block_array_t), intent(in) :: this
    integer(ip)             , intent(in) :: luout

    ! Locals
    integer(ip) :: ib
    assert(this%state == blocks_container_created)
    do ib=1, this%nblocks
       write (*,*) 'Block-vector ', ib
       call this%blocks(ib)%print(luout)
    end do
  end subroutine par_block_array_print
  
  function par_block_array_get_block (this,ib)
    implicit none
    ! Parameters
    class(par_block_array_t), target, intent(in) :: this
    integer(ip)                     , intent(in) :: ib
    type(par_scalar_array_t)        , pointer    :: par_block_array_get_block
    assert(this%state == blocks_container_created)
    par_block_array_get_block => this%blocks(ib)
  end function par_block_array_get_block

  function par_block_array_get_nblocks (this)
    implicit none
    ! Parameters
    class(par_block_array_t), target, intent(in) :: this
    integer(ip)                                  :: par_block_array_get_nblocks
    assert(this%state == blocks_container_created)
    par_block_array_get_nblocks = this%nblocks
  end function par_block_array_get_nblocks

  ! alpha <- op1^T * op2
  function par_block_array_dot(op1,op2) result(alpha)
    implicit none
    ! Parameters
    class(par_block_array_t), intent(in)  :: op1
    class(vector_t)    , intent(in)  :: op2
    real(rp) :: alpha

    ! Locals
    real(rp)    :: aux
    integer(ip) :: ib
    assert(op1%state == blocks_container_created)
    call op1%GuardTemp()
    call op2%GuardTemp()
    select type(op2)
       class is (par_block_array_t)
       assert ( op1%nblocks == op2%nblocks )
       assert(op2%state == blocks_container_created)
       alpha = 0.0_rp
       do ib=1,op1%nblocks
          aux = op1%blocks(ib)%local_dot(op2%blocks(ib))
          alpha = alpha + aux
       end do
       call op1%blocks(1)%p_env%first_level_sum(alpha)
       class default
       write(0,'(a)') 'par_block_array_t%dot: unsupported op2 class'
       check(1==0)
    end select
    call op1%CleanTemp()
    call op2%CleanTemp()
  end function par_block_array_dot
  
    ! alpha <- op1^T * op2
  function par_block_array_local_dot(op1,op2) result(alpha)
    implicit none
    ! Parameters
    class(par_block_array_t), intent(in)  :: op1
    class(vector_t)    , intent(in)  :: op2
    real(rp) :: alpha

    ! Locals
    real(rp)    :: aux
    integer(ip) :: ib
    assert(op1%state == blocks_container_created)
    call op1%GuardTemp()
    call op2%GuardTemp()
    select type(op2)
       class is (par_block_array_t)
       assert ( op1%nblocks == op2%nblocks )
       assert(op2%state == blocks_container_created)
       alpha = 0.0_rp
       do ib=1,op1%nblocks
          aux = op1%blocks(ib)%local_dot(op2%blocks(ib))
          alpha = alpha + aux
       end do
       class default
       write(0,'(a)') 'par_block_array_t%local_dot: unsupported op2 class'
       check(1==0)
    end select
    call op1%CleanTemp()
    call op2%CleanTemp()
  end function par_block_array_local_dot

  ! op1 <- op2 
  subroutine par_block_array_copy(op1,op2)
    implicit none
    ! Parameters
    class(par_block_array_t), intent(inout) :: op1
    class(vector_t)    , intent(in)    :: op2

    ! Locals
    integer(ip) :: ib
    assert(op1%state == blocks_container_created)
    call op2%GuardTemp()
    select type(op2)
       class is (par_block_array_t)
       assert ( op1%nblocks == op2%nblocks )
       assert(op2%state == blocks_container_created)
       do ib=1,op1%nblocks
          call op1%blocks(ib)%copy(op2%blocks(ib))
       end do
       class default
       write(0,'(a)') 'par_block_array_t%copy: unsupported op2 class'
       check(1==0)
    end select
    call op2%CleanTemp()
  end subroutine par_block_array_copy

  ! op <- alpha
  subroutine par_block_array_init(op,alpha)
    implicit none
    class(par_block_array_t), intent(inout) :: op 
    real(rp)                 , intent(in)    :: alpha  
    ! Locals
    integer(ip) :: ib
    assert(op%state == blocks_container_created)
    do ib=1, op%nblocks
       call op%blocks(ib)%init(alpha)
    end do
  end subroutine par_block_array_init

  ! op1 <- alpha * op2
  subroutine par_block_array_scal(op1,alpha,op2)
    implicit none
    ! Parameters 
    class(par_block_array_t), intent(inout) :: op1
    real(rp)                 , intent(in)    :: alpha
    class(vector_t)    , intent(in)    :: op2
    ! Locals
    integer(ip) :: ib
    assert(op1%state == blocks_container_created)
    call op2%GuardTemp()
    select type(op2)
       class is (par_block_array_t)
       assert ( op1%nblocks == op2%nblocks )
       assert(op2%state == blocks_container_created)
       do ib=1,op1%nblocks
          call op1%blocks(ib)%scal(alpha,op2%blocks(ib))
       end do
       class default
       write(0,'(a)') 'par_block_array_t%scal: unsupported op2 class'
       check(1==0)
    end select
    call op2%CleanTemp()
  end subroutine par_block_array_scal

  ! op1 <- alpha*op2 + beta*op1
  subroutine par_block_array_axpby(op1,alpha,op2,beta)
    implicit none
    class(par_block_array_t), intent(inout) :: op1
    real(rp)                 , intent(in)    :: alpha
    class(vector_t)    , intent(in)    :: op2
    real(rp)                 , intent(in)    :: beta
    ! Locals
    integer(ip) :: ib
    assert(op1%state == blocks_container_created)
    call op2%GuardTemp()
    select type(op2)
       class is (par_block_array_t)
       assert(op2%state == blocks_container_created)
       assert ( op1%nblocks == op2%nblocks )
       do ib=1,op1%nblocks
          call op1%blocks(ib)%axpby(alpha,op2%blocks(ib),beta)
       end do
       class default
       write(0,'(a)') 'par_block_array_t%axpby: unsupported op2 class'
       check(1==0)
    end select
    call op2%CleanTemp()
  end subroutine par_block_array_axpby

  ! alpha <- nrm2(op)
  function par_block_array_nrm2(op) result(alpha)
    implicit none
    class(par_block_array_t), intent(in) :: op
    real(rp) :: alpha
    assert(op%state == blocks_container_created)
    call op%GuardTemp()
    alpha = op%dot(op)
    alpha = sqrt(alpha)
    call op%CleanTemp()
  end function par_block_array_nrm2

  ! op1 <- clone(op2) 
  subroutine par_block_array_clone(op1,op2)
    implicit none
    ! Parameters
    class(par_block_array_t)    , intent(inout) :: op1
    class(vector_t), intent(in)    :: op2

    ! Locals
    integer(ip) :: ib
    assert(op1%state == blocks_container_created)
    call op2%GuardTemp()
    select type(op2)
       class is (par_block_array_t)
       assert(op2%state == blocks_container_created)
       call op1%free()
       call op1%create(op2%nblocks)
       do ib=1,op1%nblocks
          call op1%blocks(ib)%clone(op2%blocks(ib))
       end do
       class default
       write(0,'(a)') 'par_block_array_t%clone: unsupported op2 class'
       check(1==0)
    end select
    call op2%CleanTemp()
  end subroutine par_block_array_clone

  ! op <- comm(op)
  subroutine par_block_array_comm(op)
    implicit none
    class(par_block_array_t), intent(inout) :: op 

    ! Locals
    integer(ip) :: ib
    assert(op%state == blocks_container_created)
    do ib=1,op%nblocks
       call op%blocks(ib)%comm()
    end do

  end subroutine par_block_array_comm
  
  subroutine par_block_array_free_in_stages(this,action)
    implicit none
    class(par_block_array_t), intent(inout) :: this
    integer(ip)             , intent(in)    :: action

    integer(ip)  :: ib, istat

   if ( this%state == blocks_container_created ) then
      do ib=1, this%nblocks
         call this%blocks(ib)%free_in_stages(action)
      end do
    end if
    
    if ( action == free_clean ) then
      ! if ( this%state == not_created ) Do NOTHING
      if ( this%state == blocks_container_created ) then
        this%nblocks = 0
        deallocate( this%blocks, stat=istat )
        check(istat==0)
        this%state = not_created
      end if
    end if
    ! else if ( action == free_values ) then
    !   DO NOTHING
    ! end if
  end subroutine par_block_array_free_in_stages
  
 function par_block_array_same_vector_space(this,vector)
   implicit none
   class(par_block_array_t), intent(in) :: this
   class(vector_t), intent(in) :: vector
   logical :: par_block_array_same_vector_space
   integer(ip) :: iblk
   
   par_block_array_same_vector_space = .false.
   assert ( this%state == blocks_container_created )
   select type(vector)
   class is (par_block_array_t)
     assert ( vector%state == blocks_container_created )
     par_block_array_same_vector_space = (this%nblocks == vector%nblocks)
     if ( par_block_array_same_vector_space ) then
       do iblk=1, this%nblocks
          par_block_array_same_vector_space = this%blocks(iblk)%same_vector_space(vector%blocks(iblk))
          if ( .not. par_block_array_same_vector_space ) then
            exit
          end if
       end do
     end if
   end select
 end function par_block_array_same_vector_space
	
 function get_number_blocks(this) result(res)
   implicit none 
   class(par_block_array_t), intent(in)   :: this
   integer(ip) :: res
   res = this%nblocks
 end function get_number_blocks

end module par_block_array_names
