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
module fem_materials_class
  use types
  use memor
  use stdio
# include "debug.i90"
  implicit none
  private

  type fem_materials
     integer(ip)                :: &
          nelem=0                          ! Number of elements
     integer(ip), allocatable   :: &
          list(:)                          ! Material type for every element
  end type fem_materials

  ! Types
  public :: fem_materials

  ! Methods
  public :: fem_materials_create, fem_materials_free

contains

  !===============================================================================================
  subroutine fem_materials_create(nelem,mat)
    implicit none
    integer(ip)        , intent(in)  :: nelem
    type(fem_materials), intent(out) :: mat

    mat%nelem=nelem

    call memalloc (mat%nelem,mat%list, __FILE__,__LINE__)
    mat%list=0 

    return

  end subroutine fem_materials_create

  !===============================================================================================
  subroutine fem_materials_free(mat)
    implicit none
    type(fem_materials), intent(inout) :: mat

    mat%nelem= 0

    call memfree (mat%list,__FILE__,__LINE__)

    return

  end subroutine fem_materials_free

end module fem_materials_class
