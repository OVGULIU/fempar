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
module input_names
  use types_names
  use flap, only : Command_Line_Interface
  use FPL
# include "debug.i90"
  implicit none
  private

  ! This type implements the coupling between FPL and the cli. From a user point
  ! of view it is only necessary to extend it implementing set_default, where the 
  ! parameters required by the user have to be registered with a default value
  ! and for those that could be read from the command line register the switches,
  ! abbreviated_switches, helpers and whether they are mandatory or not.
  type input_t 
     private 
     type(Command_Line_Interface)  :: cli 
     type(ParameterList_t)         :: list
     type(ParameterList_t)         :: switches
     type(ParameterList_t)         :: switches_ab
     type(ParameterList_t)         :: helpers
     type(ParameterList_t)         :: required
   contains
     procedure, non_overridable    :: create          => input_create
     procedure                     :: set_default     => input_set_default
     procedure, non_overridable    :: add_to_cli      => input_add_to_cli
     procedure, non_overridable    :: parse           => input_parse
     procedure, non_overridable    :: free            => input_free
     procedure, non_overridable    :: get_parameters  => input_get_parameters 
     procedure, non_overridable    :: get_switches    => input_get_switches   
     procedure, non_overridable    :: get_switches_ab => input_get_switches_ab
     procedure, non_overridable    :: get_helpers     => input_get_helpers    
     procedure, non_overridable    :: get_required    => input_get_required   
  end type input_t

  public :: input_t

contains

  subroutine input_create(this)
    implicit none
    class(input_t), intent(inout) :: this
    call this%free()
     ! Initialize Command Line Interface
    call this%cli%init(progname    = 'part',                                                     &
         &        version     = '',                                                                 &
         &        authors     = '',                                                                 &
         &        license     = '',                                                                 &
         &        description =  'FEMPAR driver to part a GiD mesh.', &
         &        examples    = ['part -h  ', 'part -n  ' ])

    call this%list%init()
    call this%switches%init()
    call this%switches_ab%init()
    call this%helpers%init()
    call this%required%init()

    call this%set_default()
    call this%add_to_cli()
    call this%parse()
  end subroutine input_create

  !==================================================================================================
  subroutine input_set_default(this)
    implicit none
    class(input_t), intent(inout) :: this
    integer(ip) :: error
    ! This is necessary in derived classes implemted in the user space (here we could access
    ! member variables directly.
    type(ParameterList_t), pointer :: list, switches, switches_ab, helpers, required

    list        => this%get_parameters()
    switches    => this%get_switches()
    switches_ab => this%get_switches_ab()
    helpers     => this%get_helpers()
    required    => this%get_required()

    error = list%set(key = dir_path_key       , value = '.')      ; check(error==0);
    error = list%set(key = prefix_key         , value = 'problem'); check(error==0);

    ! Not all of them need to be controlled from cli
    error = switches%set(key = dir_path_key   , value = '--dir-path'); check(error==0);
    error = switches%set(key = prefix_key     , value = '--prefix')  ; check(error==0);

    error = switches_ab%set(key = dir_path_key, value = '-d'); check(error==0);
    error = switches_ab%set(key = prefix_key  , value = '-p'); check(error==0);

    error = helpers%set(key = dir_path_key    , value = 'Directory of the source files'); check(error==0);
    error = helpers%set(key = prefix_key      , value = 'Name of the project')          ; check(error==0);

    error = required%set(key = dir_path_key   , value = .false.); check(error==0);
    error = required%set(key = prefix_key     , value = .false.); check(error==0);
  end subroutine input_set_default

  !==================================================================================================
  function input_get_parameters(this)
    implicit none
    class(input_t), target , intent(in) :: this
    type(ParameterList_t)  , pointer    :: input_get_parameters
    input_get_parameters => this%list
  end function input_get_parameters

  !==================================================================================================
  function input_get_switches(this)
    implicit none
    class(input_t), target , intent(in) :: this
    type(ParameterList_t)  , pointer    :: input_get_switches
    input_get_switches => this%switches
  end function input_get_switches
  !==================================================================================================
  function input_get_switches_ab(this)
    implicit none
    class(input_t), target , intent(in) :: this
    type(ParameterList_t)  , pointer    :: input_get_switches_ab
    input_get_switches_ab => this%switches_ab
  end function input_get_switches_ab
  !==================================================================================================
  function input_get_helpers(this)
    implicit none
    class(input_t), target , intent(in) :: this
    type(ParameterList_t)  , pointer    :: input_get_helpers
    input_get_helpers => this%helpers
  end function input_get_helpers

  !==================================================================================================
  function input_get_required(this)
    implicit none
    class(input_t), target , intent(in) :: this
    type(ParameterList_t)  , pointer    :: input_get_required
    input_get_required => this%required
  end function input_get_required

  !==================================================================================================
  subroutine input_free(this)
    implicit none
    class(input_t), intent(inout) :: this
    call this%list%free()
    call this%switches%free()
    call this%switches_ab%free()
    call this%required%free()
    call this%cli%free()
   end subroutine input_free
  !==================================================================================================
  subroutine input_add_to_cli(this)
    implicit none
    class(input_t) , intent(inout) :: this
    integer(ip)        :: error
    character(len=512) :: switch, switch_ab, help ! , cvalue
    logical            :: required
    integer(ip)        :: ivalue
    character(len=:), allocatable :: key, cvalue !, switch, switch_ab, help
    type(ParameterListIterator_t) :: Iterator

    error = 0
    Iterator = this%switches%GetIterator()
    do while (.not. Iterator%HasFinished())
       key = Iterator%GetKey()
       error = error + Iterator%Get(switch)
       error = error + this%switches_ab%get  (key = key , value = switch_ab)
       error = error + this%helpers%get      (key = key , value = help)
       error = error + this%required%get     (key = key , value = required)
       error = error + this%list%GetAsString (key = key , string = cvalue, separator=" ")

       if(this%list%GetDimensions(Key=Iterator%GetKey()) == 0) then 
          call this%cli%add(switch=trim(switch),switch_ab=trim(switch_ab), help=trim(help), &
            &               required=required,act='store',def=trim(cvalue),error=error)
       else if(this%list%GetDimensions(Key=Iterator%GetKey()) == 1) then 
          call this%cli%add(switch=trim(switch),switch_ab=trim(switch_ab), help=trim(help), &
            &               required=required,act='store',def=trim(cvalue),error=error,nargs='5')
       else
          write(*,*) 'Rank >1 arrays not supported by CLI'
          check(.false.)
       end if
          check(error==0)
       call Iterator%Next()
    enddo

  end subroutine input_add_to_cli

  !==================================================================================================
  subroutine input_parse(this)
    implicit none
    class(input_t), intent(inout) :: this
    integer(ip)    :: istat, error
    character(512) :: switch ! , cvalue
    integer(ip)    :: ivalue

    character(len=:), allocatable :: key
    type(ParameterListIterator_t) :: Iterator
    class(*), pointer :: val0
    class(*), pointer :: val1(:)
    
    call this%cli%parse(error=error); check(error==0)

    error = 0
    Iterator = this%switches%GetIterator()
    do while (.not. Iterator%HasFinished())
       key = Iterator%GetKey()
       error = error + Iterator%Get(switch)
       if (this%cli%is_passed(switch=switch)) then
          if(this%list%GetDimensions(key = key)==0) then
             error = error + this%list%GetPointer(key = key, value=val0)
             call this%cli%get(switch=switch, val=val0, error=error)
          else if(this%list%GetDimensions(key = key)==1) then
             error = error + this%list%GetPointer(key = key, value=val1)
             call this%cli%get(switch=switch, val=val1, error=error)
          end if
       end if
       check(error==0)
       call Iterator%Next()
    enddo

  end subroutine input_parse  

end module input_names 
