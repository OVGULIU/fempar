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
module dof_distribution_create_names
  ! Serial modules  use types
  use memor
  use sort_names
  use maps_names
  use dof_import_names
  use dof_handler_names
  use dof_distribution_names
  use fem_space_types
  use fem_element_names
  use fem_space_names
  use hash_table_names

  ! Parallel modules
  use par_triangulation_names
  use psb_penv_mod

  implicit none
# include "debug.i90"
  private

  ! Functions
  public :: dof_distribution_create, create_int_objs, create_omap

contains

  !=============================================================================
  ! dhand is pointed inside femsp. It is really needed as arg?
  ! Could we eliminate this pointer inside femsp? That would require to
  ! store the problem on each element instead of an integer a id to
  ! identify it.
  !*********************************************************************************
  ! This subroutine creates the objects of DOFs on the interface between processors.
  ! An object is a the maximal set of DOFs that belong to the same processors. 
  ! The key is how to order the DOFs in an object in such a way that the ordering is
  ! identical for all processors. This way, we have the gluing info for DOFs that we
  ! need everywhere, and that, together with the local graphs, produce the 
  ! distributed graph. In order to order in a consistent way between processors, we
  ! create the following list:
  ! 
  !*********************************************************************************
  subroutine dof_distribution_create(p_trian, femsp, dhand, dof_dist)
    implicit none
    ! Parameters
    type(par_triangulation)             , intent(in)     :: p_trian
    type(fem_space)                     , intent(inout)  :: femsp
    type(dof_handler)                   , intent(in)     :: dhand
    type(dof_distribution) , allocatable, intent(out)    :: dof_dist(:)

    ! Locals
    integer(ip)               :: i, j, k, iobj, ielem, jelem, iprob, nvapb, l_var, g_var, mater, obje_l, idof, g_dof, g_mat, l_pos, iblock, ivars
    integer(ip)               :: est_max_nparts, est_max_itf_dofs
    integer(ip)               :: ipart, nparts, istat, count, nparts_around, touching
    integer(igp), allocatable :: lst_parts_per_dof_obj (:,:)
    integer(igp), allocatable :: ws_lobjs_temp (:,:)
    integer(igp), allocatable :: sort_parts_per_itfc_obj_l1 (:)
    integer(igp), allocatable :: sort_parts_per_itfc_obj_l2 (:)
    type(hash_table_ip_ip)    :: ws_parts_visited, ws_parts_visited_all
    integer(ip), parameter    :: tbl_length = 100

    integer(ip), allocatable :: touch(:,:,:)
    integer(ip), allocatable :: ws_parts_visited_list_all (:)

    integer(ip) :: max_nparts, nobjs, npadj

    integer(ip), allocatable :: l2ln2o(:), l2ln2o_ext(:), l2lo2n(:) 

    integer(ip) :: nint, nboun, l_node, inode, iobje, ndof_object

    integer(ip) :: elem_ghost, elem_local, l_var_ghost, l_var_local, nnode, obje_ghost, obje_local, order 
    integer(ip) :: o2n(max_nnode), touch_obj(femsp%num_continuity,dhand%nvars_global), k_var

!    integer(ip) :: count_interior, count_interface

    ipart  = p_trian%p_env%p_context%iam + 1
    nparts = p_trian%p_env%p_context%np

    ! Compute an estimation (upper bound) of the maximum number of parts around any local interface vef.
    ! This estimation assumes that all elements around all local interface vefs are associated to different parts.

    est_max_nparts = 0
    est_max_itf_dofs = 0
    do i=1, p_trian%num_itfc_objs
       iobj = p_trian%lst_itfc_objs(i)
       est_max_nparts = max(p_trian%f_trian%objects(iobj)%num_elems_around, est_max_nparts)       
    end do

    ! The size of the following array does not scale  
    ! properly with nparts. We should think in the meantime
    ! a strategy to keep bounded (below a local quantity) its size 

    allocate(dof_dist(dhand%nblocks), stat=istat)
    check(istat==0)


    do iblock = 1, dhand%nblocks  

       est_max_itf_dofs = 0

       do i=1, p_trian%num_itfc_objs
          iobj = p_trian%lst_itfc_objs(i)
          est_max_itf_dofs = est_max_itf_dofs + femsp%object2dof(iblock)%p(iobj+1) &
               & - femsp%object2dof(iblock)%p(iobj)
       end do


       do i=1, p_trian%num_itfc_objs
          iobj = p_trian%lst_itfc_objs(i)
          if ( p_trian%f_trian%objects(iobj)%dimension == p_trian%f_trian%num_dims - 1 ) then
             do j =1,2
                ielem = p_trian%f_trian%objects(iobj)%elems_around(j)
                iprob = femsp%lelem(ielem)%problem
                do ivars = 1,dhand%prob_block(iblock,iprob)%nd1
                   l_var = dhand%prob_block(iblock,iprob)%a(ivars)
                   if ( femsp%lelem(ielem)%continuity(l_var) == 0 ) then
                      obje_l = femsp%lelem(ielem)%f_inf(l_var)%p%nobje_dim(p_trian%f_trian%num_dims)
                      est_max_itf_dofs = est_max_itf_dofs + &
                           femsp%lelem(ielem)%f_inf(l_var)%p%ntxob%p(obje_l+1) - &
                           femsp%lelem(ielem)%f_inf(l_var)%p%ntxob%p(obje_l)
                   end if
                end do
             end do
          end if
       end do



       call memalloc ( femsp%ndofs(iblock), l2ln2o, __FILE__, __LINE__ )

       call memalloc ( nparts, ws_parts_visited_list_all, __FILE__, __LINE__ )

       call memalloc ( est_max_nparts+4, est_max_itf_dofs, lst_parts_per_dof_obj, __FILE__, __LINE__ )
       call memalloc ( est_max_nparts+3, femsp%num_continuity, dhand%nvars_global, touch, __FILE__, __LINE__ )
       call memalloc ( est_max_nparts+4, sort_parts_per_itfc_obj_l1, __FILE__,__LINE__  )  
       call memalloc ( est_max_nparts+4, sort_parts_per_itfc_obj_l2, __FILE__,__LINE__  )

       call memalloc ( est_max_itf_dofs, l2ln2o_ext, __FILE__, __LINE__ )

       call ws_parts_visited_all%init(tbl_length)

       !count_interior = 0 
       !count_interface = 0
       !max_nparts = 0

       nint = 0
       nboun = 0
       ndof_object = 0

       call list_interior_dofs ( iblock, p_trian, femsp, dhand, nint, l2ln2o )

       call ws_parts_visited_all%init(tbl_length)

       call list_interface_dofs_by_continuity ( iblock, p_trian, femsp, dhand, nboun, &
            & nint, l2ln2o, l2ln2o_ext, est_max_nparts, touch, ws_parts_visited_all, &
            &   ws_parts_visited_list_all, lst_parts_per_dof_obj, max_nparts, npadj )

       ! Initialize trivial components of dof_dist(iblock)
       dof_dist(iblock)%ipart     = ipart
       dof_dist(iblock)%nparts = nparts

       ! l2ln2o interface vefs to interface dofs from l2ln20_ext
       l2ln2o(nint+1:nint+nboun) = l2ln2o_ext(1:nboun)
       write (*,*) 'nint,nboun,ndofs',nint,nboun,femsp%ndofs(iblock) 
       assert( nint + nboun == femsp%ndofs(iblock) )  ! check
       call memfree( l2ln2o_ext, __FILE__, __LINE__ )

       write (*,*) 'l2ln2o:',l2ln2o
       write (*,*) 'max_nparts:',max_nparts

       call ws_parts_visited_all%free()

       ! Initialize max_nparts for dof_dist(iblock)%npadj
       dof_dist(iblock)%max_nparts = max_nparts

       ! Initialize npadj/lpadj for dof_dist(iblock)%npadj
       dof_dist(iblock)%npadj = npadj
       call memalloc ( dof_dist(iblock)%npadj, dof_dist(iblock)%lpadj, __FILE__, __LINE__ )
       dof_dist(iblock)%lpadj = ws_parts_visited_list_all(1:dof_dist(iblock)%npadj)

       ! write (*,*) 'npadj=', dof_dist(iblock)%npadj, 'lpadj=', dof_dist(iblock)%lpadj

       ! Re-number boundary DoFs in increasing order by physical unknown identifier, the 
       ! number of parts they belong and, for DoFs sharing the same number of parts,
       ! in increasing order by the list of parts shared by each DoF.
       call sort_array_cols_by_row_section( est_max_nparts+4,            & ! #Rows 
            &                               est_max_nparts+4,            & ! Leading dimension
            &                               nboun,                       & ! #Cols
            &                               lst_parts_per_dof_obj,       &
            &                               l2ln2o(nint+1:),             &
            &                               sort_parts_per_itfc_obj_l1,  &
            &                               sort_parts_per_itfc_obj_l2)

       ! write (*,*) 'l2ln2o:',l2ln2o

       ! Identify interface communication objects 
       call memalloc ( max_nparts+4, nboun, ws_lobjs_temp, __FILE__,__LINE__ )
       ws_lobjs_temp = 0
       if (nboun == 0) then
          nobjs=0
       else
          nobjs=1
          ws_lobjs_temp(2,nobjs) = nint+1 ! begin obj

          k = nint+1
          ! Loop over vertices of the current separator (i.e., inode)
          do i=1,nboun-1
             if(icomp( max_nparts+2,lst_parts_per_dof_obj(:,i),lst_parts_per_dof_obj(:,i+1)) /= 0) then
                ! Complete current object
                ws_lobjs_temp(1,nobjs)=lst_parts_per_dof_obj(1,i)
                ws_lobjs_temp(3,nobjs)=k ! end obj
                ws_lobjs_temp(4,nobjs)=lst_parts_per_dof_obj(2,i)
                ws_lobjs_temp(5:4+lst_parts_per_dof_obj(2,i),nobjs) = &
                     & lst_parts_per_dof_obj(3:2+lst_parts_per_dof_obj(2,i),i)

                ! Prepare next object
                nobjs=nobjs+1
                ws_lobjs_temp(2,nobjs)=k+1 ! begin obj
             end if
             k=k+1
          end do

          ! Complete last object
          ws_lobjs_temp(1,nobjs)=lst_parts_per_dof_obj(1,i)
          ws_lobjs_temp(3,nobjs)=k ! end obj
          ws_lobjs_temp(4,nobjs)=lst_parts_per_dof_obj(2,i)
          ws_lobjs_temp(5:4+lst_parts_per_dof_obj(2,i),nobjs) = &
               & lst_parts_per_dof_obj(3:2+lst_parts_per_dof_obj(2,i),i)
       end if

       ! Reallocate lobjs and add internal object first
       nobjs = nobjs + 1
       dof_dist(iblock)%nobjs = nobjs
       call memalloc (max_nparts+4, nobjs, dof_dist(iblock)%lobjs,__FILE__,__LINE__)
       dof_dist(iblock)%lobjs = 0


       ! Internal object
       dof_dist(iblock)%lobjs (1,1) = -1
       dof_dist(iblock)%lobjs (2,1) = 1
       dof_dist(iblock)%lobjs (3,1) = nint
       dof_dist(iblock)%lobjs (4,1) = 1
       dof_dist(iblock)%lobjs (5,1) = ipart
       dof_dist(iblock)%lobjs (6:max_nparts+4,1) = 0

       ! Copy ws_lobjs_temp to lobjs ...
       do i=1,nobjs-1
          dof_dist(iblock)%lobjs(:,i+1)=ws_lobjs_temp(1:(max_nparts+4), i)
       end do

       dof_dist(iblock)%nl = dof_dist(iblock)%lobjs (3,nobjs)
       dof_dist(iblock)%ni = dof_dist(iblock)%lobjs (3,1)
       dof_dist(iblock)%nb = dof_dist(iblock)%nl - dof_dist(iblock)%ni + 1

       call memfree ( ws_lobjs_temp,__FILE__,__LINE__)

       ! Auxiliary inverse of l2ln2o
       call memalloc ( femsp%ndofs(iblock), l2lo2n, __FILE__,__LINE__)

       do i=1, femsp%ndofs(iblock)
          l2lo2n(l2ln2o(i)) = i
       end do

       ! Update object2dof(iblock)
       do i = 1,femsp%object2dof(iblock)%p(p_trian%f_trian%num_objects+1)-1
          femsp%object2dof(iblock)%l(i,1) = l2lo2n(femsp%object2dof(iblock)%l(i,1))
       end do

       do ielem = 1, p_trian%f_trian%num_elems + p_trian%num_ghosts
          iprob = femsp%lelem(ielem)%problem
          nvapb = dhand%prob_block(iblock,iprob)%nd1
          do ivars = 1, nvapb
             l_var = dhand%prob_block(iblock,iprob)%a(ivars)
             do inode = 1,femsp%lelem(ielem)%f_inf(l_var)%p%nnode
                if ( femsp%lelem(ielem)%elem2dof(inode,l_var) > 0 ) then 
                   femsp%lelem(ielem)%elem2dof(inode,l_var) = l2lo2n(femsp%lelem(ielem)%elem2dof(inode,l_var))
                end if
             end do
          end do
       end do

       call memfree ( l2lo2n,__FILE__,__LINE__)
       call memfree ( l2ln2o,__FILE__,__LINE__)

       call create_int_objs ( ipart, &
            dof_dist(iblock)%npadj, &
            dof_dist(iblock)%lpadj, &
            dof_dist(iblock)%max_nparts , &
            dof_dist(iblock)%nobjs      , &
            dof_dist(iblock)%lobjs      , &
            dof_dist(iblock)%int_objs%n , &
            dof_dist(iblock)%int_objs%p , &
            dof_dist(iblock)%int_objs%l ) 

       call create_omap ( p_trian%p_env%p_context%icontxt    , & ! Communication context
            p_trian%p_env%p_context%iam         , &
            p_trian%p_env%p_context%np         , &
            dof_dist(iblock)%npadj, &
            dof_dist(iblock)%lpadj, & 
            dof_dist(iblock)%int_objs%p, &  
            dof_dist(iblock)%int_objs%l, &
            dof_dist(iblock)%max_nparts , & 
            dof_dist(iblock)%nobjs      , & 
            dof_dist(iblock)%lobjs      , &
            dof_dist(iblock)%omap%nl,     &
            dof_dist(iblock)%omap%ng,     &
            dof_dist(iblock)%omap%ni,     &
            dof_dist(iblock)%omap%nb,     &
            dof_dist(iblock)%omap%ne,     &
            dof_dist(iblock)%omap%l2g )

       call memfree ( sort_parts_per_itfc_obj_l1, __FILE__,__LINE__  )  
       call memfree ( sort_parts_per_itfc_obj_l2, __FILE__,__LINE__  )
       call memfree ( lst_parts_per_dof_obj, __FILE__, __LINE__ )
       call memfree ( touch, __FILE__, __LINE__ )
       call memfree ( ws_parts_visited_list_all, __FILE__, __LINE__ )  

       ! Compute dof_import instance within dof_dist instance such that 
       ! DoF nearest neighbour exchanges can be performed 
       call dof_distribution_compute_import(dof_dist(iblock))

    end do

  end subroutine dof_distribution_create

  integer(ip) function local_node( g_dof, iobj, elem, l_var, nobje, objects )
    implicit none
    integer(ip) :: g_dof, iobj, l_node, l_var, nobje, objects(:)
    type(fem_element) :: elem

    integer(ip) :: inode, obje_l

    do obje_l = 1, nobje
       if ( objects(obje_l) == iobj ) exit
    end do

    do inode = elem%nodes_object(l_var)%p%p(obje_l), &
         &     elem%nodes_object(l_var)%p%p(obje_l+1)-1  
       l_node = elem%nodes_object(l_var)%p%l(inode)
       if ( elem%elem2dof(l_node,l_var) == g_dof ) then
          local_node = inode - elem%nodes_object(l_var)%p%p(obje_l) + 1
          exit
       end if
    end do

  end function local_node

  subroutine create_int_objs ( ipart      , &
       npadj      , &
       lpadj      , & 
       max_nparts , &
       nobjs      , & 
       lobjs      , &
       n          , &
       p          , &
       l )
    implicit none
    integer(ip)   , intent(in)  :: ipart 
    integer(ip)   , intent(in)  :: npadj 
    integer(ip)   , intent(in)  :: lpadj(npadj)
    integer(ip)   , intent(in)  :: max_nparts
    integer(ip)   , intent(in)  :: nobjs
    integer(ip)   , intent(in)  :: lobjs(max_nparts+4,nobjs)
    integer(ip)   , intent(out) :: n
    integer(ip)   , intent(out), allocatable :: p(:)
    integer(ip)   , intent(out), allocatable :: l(:) 


!!$
!!$  ! ==========================================
!!$  ! BEGIN Compute int_objs from npadj/lpadj
!!$  ! ==========================================

    ! Locals
    integer(ip) :: i, iedge, iobj, j, jpart, iposobj
    integer(ip), allocatable :: ws_elems_list (:,:)
    integer(ip), allocatable :: ws_sort_l1 (:), ws_sort_l2 (:)

    n = npadj   
    call memalloc ( n+1, p,         __FILE__,__LINE__)

    ! Count objects on each edge of the graph of parts
    p = 0

    do iobj=1,nobjs
       do j=1,lobjs(4,iobj)
          jpart = lobjs(4+j,iobj)   ! SB.alert : Error index '9' max 8
          if (ipart /= jpart) then  ! Exclude self-edges 
             ! Locate edge identifier of ipart => jpart on the list of edges of ipart 
             iedge = 1
             do while ((lpadj(iedge) /= jpart).and. &
                  &      (iedge < npadj) )
                iedge = iedge + 1
             end do

             ! Increment by one the number of objects on the edge ipart => jpart
             p(iedge+1) = p(iedge+1) + 1 
          end if
       end do
    end do

    ! Generate pointers to the list of objects on each edge
    p(1) = 1
    do iedge=1, n
       p(iedge+1)=p(iedge+1)+p(iedge)
    end do

    ! Generate list of objects on each edge
    call memalloc (p(n+1)-1, l,            __FILE__,__LINE__)

    do iobj=1,nobjs
       do j=1,lobjs(4,iobj)
          jpart = lobjs(4+j,iobj)
          if (ipart /= jpart) then  ! Exclude self-edges 
             ! Locate edge identifier of ipart => jpart on the list of edges of ipart 
             iedge = 1
             do while ((lpadj(iedge) /= jpart).and. &
                  &      (iedge < npadj) )
                iedge = iedge + 1
             end do

             ! Insert current object on the edge ipart => jpart
             l(p(iedge)) = iobj
             p(iedge) = p(iedge) + 1 
          end if
       end do
    end do

    ! Recover p
    do iedge=n+1, 2, -1
       p(iedge) = p(iedge-1)
    end do
    p(iedge) = 1

    call memalloc ( 2, p(n+1)-1, ws_elems_list,         __FILE__,__LINE__ )

    ws_elems_list = 0 
    do iedge=1, n
       do iposobj=p(iedge),p(iedge+1)-1
          ws_elems_list(1,iposobj) = iedge
          ws_elems_list(2,iposobj) = l(iposobj)
       end do
    end do

    call memalloc ( 2, ws_sort_l1,         __FILE__,__LINE__ )

    call memalloc ( 2, ws_sort_l2,         __FILE__,__LINE__ )

    call intsort( 2,   & ! Rows of ws_parts_list_sep
         &        2,   & ! LD of ws_parts_list_sep
         &        p(n+1)-1,      & ! Cols of ws_parts_list_sep
         &        ws_elems_list,  &
         &        l, &
         &        ws_sort_l1, ws_sort_l2)



    call memfree ( ws_sort_l1,__FILE__,__LINE__)
    call memfree ( ws_sort_l2,__FILE__,__LINE__)
    call memfree ( ws_elems_list,__FILE__,__LINE__)

    write(*,'(a)') 'List of interface objects:'
    do i=1,npadj
       write(*,'(10i10)') i, &
            & (l(j),j=p(i),p(i+1)-1)
    end do

    ! ========================================
    ! END Compute int_objs from npadj/lpadj
    ! ========================================
  end subroutine create_int_objs

  subroutine create_omap ( icontxt    , & ! Communication context
       me         , &
       np         , &
       npadj      , &
       lpadj      , &
       int_objs_p , &
       int_objs_l , &
       max_nparts , & 
       nobjs      , & 
       lobjs      , &
       onl        , &
       ong        , &
       oni        , &
       onb        , &
       one        , &
       ol2g       )

#ifdef MPI_MOD
    use mpi
#endif     
    implicit none
#ifdef MPI_H
    include 'mpif.h'
#endif

    integer(ip), intent(in)               :: icontxt, me, np 
    integer(ip), intent(in)               :: npadj 
    integer(ip), intent(in)               :: lpadj(npadj)
    integer(ip), intent(in)               :: int_objs_p (npadj+1)
    integer(ip), intent(in)               :: int_objs_l (int_objs_p(npadj+1)-1)
    integer(ip), intent(in)               :: max_nparts, nobjs
    integer(ip), intent(in)               :: lobjs(max_nparts+4,nobjs)
    integer(ip), intent(out)              :: onl, ong, oni, onb, one
    integer(ip), intent(out), allocatable :: ol2g(:) 


    integer(ip) :: num_rcv             ! From how many neighbours does the part receive data ?
    integer(ip), allocatable :: &           
         list_rcv(:),           &      ! From which neighbours does the part receive data ?
         rcv_ptrs(:),           &      ! How much data does the part receive from each neighbour ?
         lids_rcv(:)                 

    integer(ip) :: num_snd             ! To how many neighbours does the part send data ? 
    integer(ip), allocatable :: &           
         list_snd(:),           &      ! To which neighbours does the part send data ?
         snd_ptrs(:),           &      ! How much data does the part send to each neighbour?
         lids_snd(:)


    integer(ip) :: ipart ! Which part am I ?
    integer(ip) :: iedge, idobj, neighbour_part_id
    integer(ip) :: iposobj, visited_snd, visited_rcv, i, j
    integer(ip) :: cur_snd, cur_rcv, sizmsg

    integer(ip)              :: nobjs_with_gid, iobj
    integer(ip), allocatable :: lobjs_with_gid(:)
    integer(ip), allocatable :: ptr_gids(:)
    integer(ip)              :: start_gid

    integer(ip), allocatable :: sndbuf(:)
    integer(ip), allocatable :: rcvbuf(:)

    ! Request handlers for non-blocking receives
    integer, allocatable, dimension(:) :: rcvhd

    ! Request handlers for non-blocking receives
    integer, allocatable, dimension(:) :: sndhd

    integer :: mpi_comm, iret, proc_to_comm
    integer :: p2pstat(mpi_status_size)
    integer, parameter :: root_pid = 0

    onl = nobjs
    oni = 1 
    onb = onl - oni
    one = 0 

    ipart = me + 1 

    num_rcv = 0
    num_snd = 0 

    cur_snd = 1
    cur_rcv = 1


    call memalloc ( npadj  , list_rcv, __FILE__,__LINE__ )
    call memalloc ( npadj+1, rcv_ptrs, __FILE__,__LINE__ )

    call memalloc ( npadj  , list_snd, __FILE__,__LINE__ )
    call memalloc ( npadj+1, snd_ptrs, __FILE__,__LINE__ )

    call memalloc ( int_objs_p(npadj+1)-1, lids_rcv, __FILE__,__LINE__ )
    call memalloc ( int_objs_p(npadj+1)-1, lids_snd, __FILE__,__LINE__ )

    ! Traverse ipart's neighbours in the graph of parts
    do iedge = 1, npadj
       neighbour_part_id = lpadj (iedge)

       visited_snd = 0 
       visited_rcv = 0 

       ! write(*,*) 'PPP', ipart, neighbour_part_id, int_objs_p(iedge), int_objs_p(iedge+1)

       ! Traverse list of objects on the current edge
       do iposobj=int_objs_p(iedge), int_objs_p(iedge+1)-1
          idobj = int_objs_l (iposobj)

          ! write (*,*) 'ZZZ', idobj, ipart, lobjs(5,idobj)
          ! write(*,*) 'XXX', ipart, neighbour_part_id, idobj ! DBG:
          if ( ipart == lobjs(5,idobj) ) then                       ! ipart has to send global object id to neighbour_part_id
             if ( visited_snd == 0 ) then
                ! No 
                num_snd = num_snd + 1 
                list_snd (num_snd) = neighbour_part_id              
                snd_ptrs (num_snd+1) = 1
                visited_snd = 1 
             else
                ! Yes
                snd_ptrs (num_snd+1) = snd_ptrs(num_snd+1) + 1
             end if
             lids_snd(cur_snd)=idobj
             cur_snd = cur_snd + 1
          else if ( neighbour_part_id == lobjs(5,idobj) ) then      ! ipart has to receive global object id from neighbour_part_id
             if ( visited_rcv == 0 ) then
                ! No 
                num_rcv = num_rcv + 1 
                list_rcv (num_rcv) = neighbour_part_id
                rcv_ptrs (num_rcv+1) = 1
                visited_rcv = 1 
             else
                ! Yes
                rcv_ptrs (num_rcv+1) = rcv_ptrs(num_rcv+1) + 1
             end if
             lids_rcv(cur_rcv)=idobj
             cur_rcv = cur_rcv + 1
             ! else ! Nothing to be sent from ipart/received from neighbour_part_id 
          end if
       end do   ! iposobj
    end do     ! iedge

    ! write(*,*) 'XXX', list_snd(1:num_snd)
    ! write(*,*) 'YYY', list_rcv(1:num_rcv)


    ! Transform rcv_ptrs from size to pointers
    rcv_ptrs(1) = 1
    do i = 1, num_rcv
       rcv_ptrs (i+1) = rcv_ptrs (i+1) + rcv_ptrs (i)  
    end do

    ! Transform snd_ptrs from size to pointers
    snd_ptrs(1) = 1
    do i = 1, num_snd
       snd_ptrs (i+1) = snd_ptrs(i+1) + snd_ptrs (i)  
    end do

!!$    write (*,*) 'num_rcv' , num_rcv
!!$    write (*,*) 'rcv_ptrs', rcv_ptrs(1:num_rcv+1)
!!$    write (*,*) 'lst_rcv' , list_rcv (1:num_rcv)
!!$    write (*,*) 'lids_rcv', lids_rcv(1:rcv_ptrs(num_rcv+1)-1)
!!$
!!$    write (*,*) 'num_snd' , num_snd
!!$    write (*,*) 'snd_ptrs', snd_ptrs(1:num_snd+1)
!!$    write (*,*) 'lst_snd' , list_snd (1:num_snd)
!!$    write (*,*) 'lids_snd', lids_snd(1:snd_ptrs(num_snd+1)-1)


    ! 1. Count/List how many local objects i have to identify a global id
    nobjs_with_gid = 0
    call memalloc (nobjs, lobjs_with_gid, __FILE__,__LINE__)

    do iobj = 1, nobjs
       if ( ipart == lobjs(5, iobj) ) then
          nobjs_with_gid = nobjs_with_gid + 1
          lobjs_with_gid(nobjs_with_gid) = iobj
       end if
    end do

    !! write (*,*) 'XX', lobjs_with_gid(1:nobjs_with_gid)

    ! 2. Gather + Scatter
    ! Get MPI communicator associated to icontxt (in
    ! the current implementation of our wrappers
    ! to the MPI library icontxt and mpi_comm are actually 
    ! the same)
    call psb_get_mpicomm (icontxt, mpi_comm)

    if ( me == root_pid ) then
       call memalloc( np+1, ptr_gids, __FILE__,__LINE__ )
       call mpi_gather( nobjs_with_gid  , 1, psb_mpi_integer,  &
            ptr_gids(2:np+1), 1, psb_mpi_integer, root_pid, mpi_comm, iret)
    else
       call memalloc( 0, ptr_gids, __FILE__,__LINE__ )
       call mpi_gather( nobjs_with_gid  , 1, psb_mpi_integer,  &
            ptr_gids        , 1, psb_mpi_integer, root_pid, mpi_comm, iret)
    end if

    if ( iret /= mpi_success ) then
       write (0,*) 'Error: mpi_gather returned != mpi_success'
       call psb_abort (icontxt)    
    end if

    if ( me == root_pid ) then
       ! Transform length to header
       ptr_gids(1)=1 
       do i=1, np
          ptr_gids(i+1) = ptr_gids(i) + ptr_gids(i+1) 
       end do
       ong = ptr_gids(np+1)-1 
       ! write (*,*) 'XXX', ptr_coarse_dofs(1:np+1) ! DBG:
    end if

    call psb_bcast ( icontxt, ong, root=root_pid)

    call mpi_scatter  ( ptr_gids , 1, psb_mpi_integer, &
         start_gid, 1, psb_mpi_integer, &
         root_pid , mpi_comm, iret )


    call memalloc( onl, ol2g, __FILE__,__LINE__ )


    ol2g = -1 

    ! 3. Assign global id to my "local" objects
    do i=1, nobjs_with_gid
       ol2g(lobjs_with_gid(i))=start_gid
       start_gid = start_gid + 1
    end do


    ! 4. Nearest neighbour comm
    call memalloc (num_rcv, rcvhd, __FILE__,__LINE__)
    call memalloc (num_snd, sndhd, __FILE__,__LINE__)

    call memalloc (snd_ptrs(num_snd+1)-snd_ptrs(1), sndbuf, __FILE__,__LINE__)
    call memalloc (rcv_ptrs(num_rcv+1)-rcv_ptrs(1), rcvbuf, __FILE__,__LINE__)

    ! Pack sndbuf
    do i=1, snd_ptrs(num_snd+1)-1
       sndbuf(i) = ol2g(lids_snd(i))
    end do

    ! First post all the non blocking receives   
    do i=1, num_rcv
       proc_to_comm = list_rcv(i)

       ! Get MPI rank id associated to proc_to_comm - 1 in proc_to_comm
       call psb_get_rank (proc_to_comm, icontxt, proc_to_comm-1)

       ! Message size to be received
       sizmsg = rcv_ptrs(i+1)-rcv_ptrs(i)

       call mpi_irecv(  rcvbuf(rcv_ptrs(i)), sizmsg,        &
            &        psb_mpi_integer, proc_to_comm, &
            &        psb_int_swap_tag, mpi_comm, rcvhd(i), iret)

       if ( iret /= mpi_success ) then
          write (0,*) 'Error: mpi_irecv returned != mpi_success'
          call psb_abort (icontxt)    
       end if
    end do

    ! Secondly post all non-blocking sends
    do i=1, num_snd
       proc_to_comm = list_snd(i)

       ! Get MPI rank id associated to proc_to_comm - 1 in proc_to_comm
       call psb_get_rank (proc_to_comm, icontxt, proc_to_comm-1)

       ! Message size to be sent
       sizmsg = snd_ptrs(i+1)-snd_ptrs(i)

       call mpi_isend(sndbuf(snd_ptrs(i)), sizmsg, &
            & psb_mpi_integer, proc_to_comm,    &
            & psb_int_swap_tag, mpi_comm, sndhd(i), iret)

       if ( iret /= mpi_success ) then
          write (0,*) 'Error: mpi_isend returned != mpi_success'
          call psb_abort (icontxt)    
       end if
    end do

    ! Wait on all non-blocking receives
    do i=1, num_rcv
       proc_to_comm = list_rcv(i)

       ! Get MPI rank id associated to proc_to_comm - 1 in proc_to_comm
       call psb_get_rank (proc_to_comm, icontxt, proc_to_comm-1)

       ! Message size to be received
       sizmsg = rcv_ptrs(i+1)-rcv_ptrs(i)

       call mpi_wait(rcvhd(i), p2pstat, iret)

       if ( iret /= mpi_success ) then
          write (0,*) 'Error: mpi_wait returned != mpi_success'
          call psb_abort (icontxt)    
       end if

    end do

    ! Finally wait on all non-blocking sends
    do i=1, num_snd
       proc_to_comm = list_snd(i)

       ! Get MPI rank id associated to proc_to_comm - 1 in proc_to_comm
       call psb_get_rank (proc_to_comm, icontxt, proc_to_comm-1)

       ! Message size to be received
       sizmsg = snd_ptrs(i+1)-snd_ptrs(i)

       call mpi_wait(sndhd(i), p2pstat, iret)
       if ( iret /= mpi_success ) then
          write (0,*) 'Error: mpi_wait returned != mpi_success'
          call psb_abort (icontxt)    
       end if
    end do


    ! 5. Assign global id to "remote"  objects
    ! Pack sndbuf
    do i=1, rcv_ptrs(num_rcv+1)-1
       ol2g(lids_rcv(i)) = rcvbuf(i) 
    end do

    ! do i=1, npadj
    !   write (*,*) 'neig', lpadj(i)
    !   do j=int_objs_p(i),int_objs_p(i+1)-1
    !      write (*,*) 'PPP', int_objs_l(j), lobjs(2,int_objs_l(j)), ol2g(int_objs_l(j))
    !   end do
    ! end do

    call memfree( ptr_gids, __FILE__,__LINE__ )

    call memfree (rcvhd,__FILE__,__LINE__) 
    call memfree (sndhd,__FILE__,__LINE__)

    call memfree (sndbuf,__FILE__,__LINE__)
    call memfree (rcvbuf,__FILE__,__LINE__)

    call memfree ( list_rcv,__FILE__,__LINE__)
    call memfree ( rcv_ptrs,__FILE__,__LINE__)

    call memfree ( list_snd,__FILE__,__LINE__)
    call memfree ( snd_ptrs,__FILE__,__LINE__)

    call memfree ( lids_rcv,__FILE__,__LINE__)
    call memfree ( lids_snd,__FILE__,__LINE__)

    call memfree (lobjs_with_gid,__FILE__,__LINE__)

!!$  do i=1, npadj
!!$     write (*,*) 'neig', lpadj(i)
!!$     do j=int_objs_p(i),int_objs_p(i+1)-1
!!$        write (*,*) ol2g(int_objs_l(j))
!!$     end do
!!$  end do

  end subroutine create_omap


  subroutine list_interior_dofs ( iblock, p_trian, femsp, dhand, count_interior, l2ln2o )
    implicit none
    ! Parameters
    integer(ip), intent(in)                     :: iblock
    type(par_triangulation), intent(in)         :: p_trian 
    type(fem_space), intent(in)                 :: femsp
    type(dof_handler), intent(in)               :: dhand
    integer(ip), intent(inout)                  :: count_interior, l2ln2o(:)

    ! Local variables
    integer(ip) :: iobj, idof, ielem, iprob, nvapb, ivars, l_var, g_var, iobje, inode, l_node

    do iobj = 1, p_trian%f_trian%num_objects
       if ( p_trian%objects(iobj)%interface == -1 ) then
          do idof = femsp%object2dof(iblock)%p(iobj), femsp%object2dof(iblock)%p(iobj+1)-1
             count_interior = count_interior + 1
             l2ln2o(count_interior) = femsp%object2dof(iblock)%l(idof,1) 
             !write(*,*) 'l2ln2o',l2ln2o
          end do
       end if
    end do


    ! interior vol
    if ( .not. femsp%static_condensation ) then 
       do ielem = 1, p_trian%f_trian%num_elems
          iprob = femsp%lelem(ielem)%problem
          nvapb = dhand%prob_block(iblock,iprob)%nd1
          do ivars = 1, nvapb
             l_var = dhand%prob_block(iblock,iprob)%a(ivars)
             g_var = dhand%problems(iprob)%p%l2g_var(l_var)  
             if ( femsp%lelem(ielem)%continuity(g_var) /= 0 .or. &
                  & p_trian%elems(ielem)%interface == -1 ) then
                ! Be careful, this is not true for dG elements on the interface
                iobje = p_trian%f_trian%elems(ielem)%num_objects+1
                do inode = femsp%lelem(ielem)%nodes_object(l_var)%p%p(iobje), &
                     &     femsp%lelem(ielem)%nodes_object(l_var)%p%p(iobje+1)-1 
                   l_node = femsp%lelem(ielem)%nodes_object(l_var)%p%l(inode)
                   count_interior = count_interior + 1
                   l2ln2o(count_interior) = femsp%lelem(ielem)%elem2dof(l_node,l_var) 
                end do
             end if
          end do
       end do
    end if

  end subroutine list_interior_dofs

  subroutine list_interface_dofs_by_continuity ( iblock, p_trian, femsp, dhand, count_interface, &
       & count_interior, l2ln2o_interior, l2ln2o_interface, est_max_nparts, touch, ws_parts_visited_all, &
       &   ws_parts_visited_list_all, lst_parts_per_dof_obj, max_nparts, npadj )
    implicit none
    ! Parameters
    integer(ip), intent(in)                     :: iblock
    type(par_triangulation), intent(in)         :: p_trian 
    type(fem_space), intent(in)                 :: femsp
    type(dof_handler), intent(in)               :: dhand
    integer(ip), intent(inout)                  :: count_interface, count_interior, l2ln2o_interior(:), l2ln2o_interface(:)
    integer(ip), intent(inout)                  :: est_max_nparts, touch(:,:,:)
    type(hash_table_ip_ip), intent(inout)       :: ws_parts_visited_all
    integer(ip), intent(inout)                  :: ws_parts_visited_list_all(:), max_nparts, npadj
    integer(igp), intent(inout)                  :: lst_parts_per_dof_obj(:,:)

    ! Local variables
    integer(ip) :: i, iobje, j, idof, g_var
    integer(ip) :: mater, k, ielem, iprob, ivars, l_var, k_var  
    integer(ip) :: touching, obje_l, istat, g_dof, g_mat, ipart, l_pos, nparts_around, count
    type(hash_table_ip_ip)         :: ws_parts_visited
    integer(ip), parameter    :: tbl_length = 100

    ipart  = p_trian%p_env%p_context%iam + 1

    npadj = 0
    touching = 1
    !count_interface = 0
    count = 0
    do i = 1, p_trian%num_itfc_objs
       !touch_obj = 0
       iobje = p_trian%lst_itfc_objs(i)
       mater = 0 
       touch = 0

       call ws_parts_visited%init(tbl_length)

       do k = 1, p_trian%f_trian%objects(iobje)%num_elems_around

          ielem = p_trian%f_trian%objects(iobje)%elems_around(k)
          iprob = femsp%lelem(ielem)%problem

          do ivars = 1,dhand%prob_block(iblock,iprob)%nd1
             l_var = dhand%prob_block(iblock,iprob)%a(ivars)

             if ( femsp%lelem(ielem)%continuity(l_var) /= 0 ) then

                g_var = dhand%problems(iprob)%p%l2g_var(l_var)
                mater = femsp%lelem(ielem)%material ! SB.alert : material can be used as p 

                obje_l = local_position( iobje, p_trian%f_trian%elems(ielem)%objects, &
                     &                   p_trian%f_trian%elems(ielem)%num_objects )


                call ws_parts_visited%put(key=p_trian%elems(ielem)%mypart,val=touching,stat=istat)
                if ( istat == now_stored ) then
                   touch(1,mater,g_var) = touch(1,mater,g_var) + 1 ! New part in the counter  
                   write(*,*) 'touch',touch
                   touch(touch(mater,g_var,1)+3,mater,g_var) = p_trian%elems(ielem)%mypart ! Put new part
                end if
                if( p_trian%elems(ielem)%globalID > touch(2,mater,g_var) ) then
                   touch(2,mater,g_var) = ielem 
                   touch(3,mater,g_var) = obje_l
                end if
                if ( p_trian%elems(ielem)%mypart /= ipart ) then
                   !call ws_parts_visited_all%put(key=p_trian%elems(ielem)%mypart,val=1,stat=istat)
                   write (*,*) 'p_trian%elems(ielem)%mypart', p_trian%elems(ielem)%mypart
                   call ws_parts_visited_all%put(key=p_trian%elems(ielem)%mypart,val=touching,stat=istat)
                   write (*,*) 'istat',istat
                   if ( istat == now_stored ) then
                      npadj = npadj + 1
                      ws_parts_visited_list_all(npadj) = p_trian%elems(ielem)%mypart
                   end if
                end if

             end if
          end do
       end do
       if (mater > 0) then
          max_nparts = max(max_nparts, touch(1,mater,g_var))
       end if

       !write(*,*) '**** TOUCH ****',touch
       ! Sort list of parts in increasing order by part identifiers
       ! This is required by the call to icomp subroutine below 
       do mater = 1, femsp%num_continuity
          do g_var = 1, dhand%nvars_global
             call sort ( touch(1,mater,g_var), touch(4:(touch(mater,g_var,1)+3),mater,g_var) )
          end do
       end do

       !p_trian%max_nparts = max(p_trian%max_nparts, count)
       call ws_parts_visited%free


       do idof = femsp%object2dof(iblock)%p(iobje), femsp%object2dof(iblock)%p(iobje+1)-1
          ! parts
          g_var = femsp%object2dof(iblock)%l(idof,2)  
          g_mat = femsp%object2dof(iblock)%l(idof,3)
          !write(*,*) 'g_mat',g_mat
          if ( touch(1,g_mat,g_var) > 1 ) then ! Interface dof
             g_dof = femsp%object2dof(iblock)%l(idof,1)
             nparts_around = touch(1,g_mat,g_var)

             count = count + 1
             lst_parts_per_dof_obj (1,count) = g_var ! Variable

             ! Use the local pos of dof in elem w/ max GID to sort
             l_var = dhand%g2l_vars(g_var,femsp%lelem(touch(2,g_mat,g_var))%problem)

             l_pos =  local_node( g_dof, iobje, femsp%lelem(touch(2,g_mat,g_var)), l_var, &
                  & p_trian%f_trian%elems(touch(2,g_mat,g_var))%num_objects, &
                  & p_trian%f_trian%elems(touch(2,g_mat,g_var))%objects )
             lst_parts_per_dof_obj (2,count) = nparts_around ! Number parts 
             lst_parts_per_dof_obj (3:(nparts_around+2),count) = touch(4:(touch(g_mat,g_var,1)+3),g_mat,g_var) ! List parts
             lst_parts_per_dof_obj (nparts_around+3:est_max_nparts+2,count) = 0 ! Zero the rest of entries in current col except last
             lst_parts_per_dof_obj (est_max_nparts+3,count) = p_trian%objects(iobje)%globalID
             lst_parts_per_dof_obj (est_max_nparts+4,count) = l_pos ! Local pos in Max elem GID

             ! l2ln2o interface vefs to interface dofs
             count_interface = count_interface + 1
             write(*,*) 'count_interface',count_interface
             l2ln2o_interface(count_interface) = femsp%object2dof(iblock)%l(idof,1)                  
          else
             ! l2ln2o interface vefs to interior dofs
             count_interior = count_interior + 1
             l2ln2o_interior(count_interior) = femsp%object2dof(iblock)%l(idof,1)  
          end if
       end do

    end do

!!!!!!


    !    !write(*,*) 'interface object',iobje
    !    do j = femsp%object2dof(iblock)%p(iobje),femsp%object2dof(iblock)%p(iobje+1)-1
    !       idof = femsp%object2dof(iblock)%l(j,1)
    !       g_var = femsp%object2dof(iblock)%l(j,2)
    !       mater= femsp%object2dof(iblock)%l(j,3)
    !       !write(*,*) 'idof,g_var,mater',idof,g_var,mater
    !       !write(*,*) 'touch,',touch_obj
    !       if ( touch_obj(g_var,mater) == 1 ) then
    !          count_interface = count_interface + 1
    !       else if ( touch_obj(g_var,mater) == 0) then             
    !          do k = 1, p_trian%f_trian%objects(iobje)%num_elems_around
    !             ielem = p_trian%f_trian%objects(iobje)%elems_around(k)
    !             if ( ielem >  p_trian%f_trian%num_elems ) then
    !                iprob = femsp%lelem(ielem)%problem
    !                !write(*,*) 'ghost elem',ielem
    !                if ( femsp%lelem(ielem)%continuity(g_var) == mater ) then
    !                   do ivars = 1,dhand%prob_block(iblock,iprob)%nd1
    !                      l_var = dhand%prob_block(iblock,iprob)%a(ivars)
    !                      k_var = dhand%problems(iprob)%p%l2g_var(l_var)
    !                      if (k_var == g_var ) then
    !                         count_interface = count_interface + 1
    !                         touch_obj(g_var,mater) = 1
    !                         exit
    !                      end if
    !                   end do
    !                end if
    !                if ( touch_obj(g_var,mater) == 1 ) exit
    !             end if
    !          end do
    !          if ( touch_obj(g_var,mater) == 0 )  touch_obj(g_var,mater) = -1
    !       end if
    !    end do
    !    ! Put non-selected DOFs on the interior
    !    do j = femsp%object2dof(iblock)%p(iobje),femsp%object2dof(iblock)%p(iobje+1)-1
    !       idof = femsp%object2dof(iblock)%l(j,1)
    !       g_var = femsp%object2dof(iblock)%l(j,2)
    !       mater= femsp%object2dof(iblock)%l(j,3)
    !       if ( touch_obj(g_var,mater) == 0 ) then
    !          count_interior = count_interior + 1
    !          l2ln2o(count_interior) = idof
    !       end if
    !    end do
    ! end do

  end subroutine list_interface_dofs_by_continuity


  subroutine list_interface_dofs_by_face_integration ( iblock, p_trian, femsp, dhand, count_interface, &
       & count_interior, count_obj_dof, l2ln2o_interior, l2ln2o_interface, est_max_nparts, ws_parts_visited_all, &
       &   ws_parts_visited_list_all, lst_parts_per_dof_obj, max_nparts, npadj )
    implicit none
    ! Parameters
    integer(ip), intent(in)                     :: iblock
    type(par_triangulation), intent(in)         :: p_trian 
    type(fem_space), intent(in)                 :: femsp
    type(dof_handler), intent(in)               :: dhand
    integer(ip), intent(inout)                  :: count_interface, count_interior, count_obj_dof
    integer(ip), intent(inout)                  :: l2ln2o_interior(:), l2ln2o_interface(:), est_max_nparts
    type(hash_table_ip_ip), intent(inout)       :: ws_parts_visited_all
    integer(ip), intent(inout)                  :: ws_parts_visited_list_all(:), max_nparts, npadj
    integer(igp), intent(inout)                  :: lst_parts_per_dof_obj(:,:)

    ! Local variables
    integer(ip) :: i, ipart, ielem, iprob, aux(2), ivars, l_var, g_var, obje_l, iobje, j, jelem, inode, l_node, istat, jobje
    integer(ip) :: touch(28), l_obj2 ! max_nobje

    ipart  = p_trian%p_env%p_context%iam + 1
    count_obj_dof = count_interface

    touch = 0
    ! Additional interface DOFs due to local dG elements
    do i = 1, p_trian%num_itfc_elems + p_trian%num_ghosts ! loop on interface and ghost elements
       if ( i <= p_trian%num_elems ) then
          ielem = p_trian%lst_itfc_elems(i)                      ! interface element
       else
          ielem = i - p_trian%num_itfc_elems + p_trian%num_elems ! ghost element
       end if
       iprob = femsp%lelem(ielem)%problem 
       aux(1) = ipart
       !femsp%lelem(ielem)%p_vec%a = 0.0_rp ! Used as touch array
       do ivars = 1, dhand%prob_block(iblock,iprob)%nd1
          l_var = dhand%prob_block(iblock,iprob)%a(ivars) 
          g_var = dhand%problems(iprob)%p%l2g_var(l_var)
          if ( femsp%lelem(ielem)%continuity(g_var) == 0 ) then ! dG local element on the interface
             ! Identify and put interface DOFs
             do obje_l = p_trian%f_trian%elems(ielem)%topology%nobje_dim(p_trian%f_trian%num_dims), &
                  &      p_trian%f_trian%elems(ielem)%topology%nobje_dim(p_trian%f_trian%num_dims+1)-1
                iobje = p_trian%f_trian%elems(ielem)%objects(obje_l)
                ! iobje is a face by construction
                assert ( p_trian%f_trian%objects(iobje)%dimension == p_trian%f_trian%num_dims - 1 )
                if ( p_trian%objects(iobje)%interface /= -1 ) then
                   ! if face on the interface
                   assert ( p_trian%f_trian%objects(iobje)%num_elems_around == 2 )
                   do j = 1,2
                      jelem = p_trian%f_trian%objects(iobje)%elems_around(j)
                      if ( jelem /= ielem ) aux(2) = p_trian%elems(jelem)%mypart
                      !aux = sort( aux )
                   end do
                   assert ( aux(1) /= aux(2) )
                   call ws_parts_visited_all%put(key=p_trian%elems(ielem)%mypart,val=1,stat=istat)
                   !write (*,*) 'p_trian%elems(ielem)%mypart', p_trian%elems(ielem)%mypart
                   call ws_parts_visited_all%put(key=aux(2),val=1,stat=istat)
                   !write (*,*) 'istat',istat
                   if ( istat == now_stored ) then
                      npadj = npadj + 1
                      ws_parts_visited_list_all(npadj) = aux(2)
                   end if
                   do jobje = femsp%lelem(ielem)%f_inf(l_var)%p%obxob%p(obje_l), &
                        & femsp%lelem(ielem)%f_inf(l_var)%p%obxob%p(obje_l+1)-1
                      l_obj2 = femsp%lelem(ielem)%f_inf(l_var)%p%obxob%l(jobje)
                      do inode = femsp%lelem(ielem)%f_inf(l_var)%p%ndxob%p(l_obj2), &
                           & femsp%lelem(ielem)%f_inf(l_var)%p%ndxob%p(l_obj2+1)-1
                         l_node = femsp%lelem(ielem)%f_inf(l_var)%p%ndxob%l(inode)
                         if ( touch(l_obj2) == 0 ) then
                            count_interface = count_interface + 1
                            l2ln2o_interface(count_interface) = femsp%lelem(ielem)%elem2dof(l_node,l_var)
                            touch(l_obj2) = count_interface
                         end if
                         count_obj_dof = count_obj_dof + 1
                         lst_parts_per_dof_obj (1,count_obj_dof) = g_var ! Variable
                         lst_parts_per_dof_obj (2,count_obj_dof) = 2 ! Number parts 
                         call sort( 2, aux ) 
                         lst_parts_per_dof_obj (3,count_obj_dof) = aux(1) ! Put new part
                         lst_parts_per_dof_obj (4,count_obj_dof) = aux(2) ! Put new part
                         lst_parts_per_dof_obj (5:est_max_nparts+2,count_obj_dof) = 0 
                         ! Cuidado: HABLA CON ALBERTO
                         lst_parts_per_dof_obj (est_max_nparts+3,count_obj_dof) = p_trian%objects(iobje)%globalID
                         lst_parts_per_dof_obj (est_max_nparts+4,count_obj_dof) = l_node
                      end do
                   end do
                end if
             end do
             touch = 0
          end if
       end do
    end do

  end subroutine list_interface_dofs_by_face_integration

    ! ! Additional interface DOFs due to ghost dG elements
    ! do ielem = p_trian%num_elems+1, p_trian%num_elems+p_trian%num_ghosts
    !    aux(1) = ipart
    !    !write (*,*) 'ghost element', ielem
    !    !write (*,*) 'femsp%lelem(ielem)%elem2dof', femsp%lelem(ielem)%elem2dof
    !    aux(2) = p_trian%elems(ielem)%mypart
    !    aux = sort(aux)
    !    iprob = femsp%lelem(ielem)%problem  
    !    do ivars = 1, dhand%prob_block(iblock,iprob)%nd1
    !       l_var = dhand%prob_block(iblock,iprob)%a(ivars) 
    !       g_var = dhand%problems(iprob)%p%l2g_var(l_var)
    !       !write (*,*) 'ivars', ivars
    !       if ( femsp%lelem(ielem)%continuity(g_var) == 0 ) then ! dG ghost element on the interface


    !          do obje_l = p_trian%f_trian%elems(ielem)%topology%nobje_dim(p_trian%f_trian%num_dims), &
    !               &      p_trian%f_trian%elems(ielem)%topology%nobje_dim(p_trian%f_trian%num_dims+1)-1
    !             iobje = p_trian%f_trian%elems(ielem)%objects(obje_l)
    !             ! iobje is a face by construction
    !             if ( iobje /= -1 ) then
    !                assert ( p_trian%f_trian%objects(iobje)%dimension == p_trian%f_trian%num_dims - 1 )
    !                assert ( p_trian%objects(iobje)%interface /= -1 )
    !                do inode = femsp%lelem(ielem)%f_inf(l_var)%p%ntxob%p(obje_l), &
    !                     & femsp%lelem(ielem)%f_inf(l_var)%p%ntxob%p(obje_l+1)-1
    !                   l_node = femsp%lelem(ielem)%f_inf(l_var)%p%ntxob%l(inode)
    !                   if ( femsp%lelem(ielem)%elem2dof(l_node,l_var) /= 0 ) then
    !                      if ( touch(l_node) == 0 ) then
    !                         count_interface = count_interface + 1
    !                         touch(l_node) = count_interface
    !                         l2ln2o_interface(count_interface) = femsp%lelem(ielem)%elem2dof(inode,l_var)
    !                         nparts_around = 2
    !                         lst_parts_per_dof_obj (1,count_interface) = g_var ! Variable
    !                         lst_parts_per_dof_obj (2,count_interface) = 2 ! Number parts 
    !                         lst_parts_per_dof_obj (3:4,count_interface) = aux ! List parts
    !                         lst_parts_per_dof_obj (5:est_max_nparts+2,count_interface) = 0 ! Zero the rest of entries in current col except last
    !                         ! Cuidado: HABLA CON ALBERTO

    !                         ESTA PARTE ESTA MAL, NO ESTA A FUEGO EL 2

    !                         lst_parts_per_dof_obj (est_max_nparts+3,count) = p_trian%objects(iobje)%globalID
    !                         lst_parts_per_dof_obj (est_max_nparts+3,count) = p_trian%elems(ielem)%globalID
    !                         lst_parts_per_dof_obj (est_max_nparts+4,count) = inode

    !                      end if
    !                   end do
    !                end if
    !             end do
    !          end do
    !       end if
    !    end do
    ! end do

    ! ! Additional interface DOFs due to local dG elements
    ! do i = 1, p_trian%num_itfc_elems

    !    ielem = p_trian%lst_itfc_elems(i)          
    !    assert ( ielem <= p_trian%num_elems )
    !    iprob = femsp%lelem(ielem)%problem 
    !    aux(1) = ipart
    !
    !    femsp%lelem(ielem)%p_vec%a = 0.0_rp ! Used as touch array

    !    do ivars = 1, dhand%prob_block(iblock,iprob)%nd1
    !       l_var = dhand%prob_block(iblock,iprob)%a(ivars) 
    !       g_var = dhand%problems(iprob)%p%l2g_var(l_var)
    !       if ( femsp%lelem(ielem)%continuity(g_var) == 0 ) then ! dG local element on the interface
    !          ! Identify and put interface DOFs

    !          touch ( nnode ) = 0


    !          do obje_l = p_trian%f_trian%elems(ielem)%topology%nobje_dim(p_trian%f_trian%num_dims), &
    !               &      p_trian%f_trian%elems(ielem)%topology%nobje_dim(p_trian%f_trian%num_dims+1)-1
    !             iobje = p_trian%f_trian%elems(ielem)%objects(obje_l)
    !             ! iobje is a face by construction
    !             assert ( p_trian%f_trian%objects(iobje)%dimension == p_trian%f_trian%num_dims - 1 )
    !             if ( p_trian%objects(iobje)%interface /= -1 ) then
    !                ! if face on the interface
    !                !do object in face

    !                !end do
    !                aux(1) = ipart
    !                assert ( p_trian%f_trian%objects(iobje)%num_elems_around == 2 )
    !                do j = 1,2
    !                   jelem = p_trian%f_trian%objects(iobje)%elems_around(j)
    !                   if ( jelem /= ielem ) aux(2) = p_trian%elems(jelem)%mypart
    !                   !aux = sort( aux )
    !                end do
    !                assert ( aux(1) /= aux(2) )
    !                if ( aux(2) /= ipart ) then
    !                   !call ws_parts_visited_all%put(key=p_trian%elems(ielem)%mypart,val=1,stat=istat)
    !                   write (*,*) 'p_trian%elems(ielem)%mypart', p_trian%elems(ielem)%mypart
    !                   call ws_parts_visited_all%put(key=aux(2),val=1,stat=istat)
    !                   write (*,*) 'istat',istat
    !                   if ( istat == now_stored ) then
    !                      npadj = npadj + 1
    !                      ws_parts_visited_list_all(npadj) = aux(2)
    !                   end if
    !                end if
    !                do inode = femsp%lelem(ielem)%f_inf(l_var)%p%ntxob%p(obje_l), &
    !                     & femsp%lelem(ielem)%f_inf(l_var)%p%ntxob%p(obje_l+1)-1
    !                   l_node = femsp%lelem(ielem)%f_inf(l_var)%p%ntxob%l(inode)

    !                   istat = now_stored

    !                   if ( touch(l_node) == 0 ) then
    !                      count_interface = count_interface + 1
    !                      l2ln2o_interface(count_interface) = femsp%lelem(ielem)%elem2dof(l_node,l_var)
    !                      touch( l_node ) = count_interface
    !                      lst_parts_per_dof_obj (1,count_interface) = g_var ! Variable
    !                      lst_parts_per_dof_obj (2,count_interface) = 2 ! Number parts  
    !                      lst_parts_per_dof_obj (3,count_interface) = aux(1) ! Put new part
    !                      lst_parts_per_dof_obj (4,count_interface) = aux(2) ! Put new part

    !                      ! Cuidado: HABLA CON ALBERTO

    !                      lst_parts_per_dof_obj (est_max_nparts+3,count) = p_trian%objects(iobje)%globalID
    !                      lst_parts_per_dof_obj (est_max_nparts+4,count) = l_node
    !                   end if


    !                   do k = 3, lst_parts_per_dof_obj (2,touch(l_node))+2
    !                      if ( aux(2) == lst_parts_per_dof_obj(k,touch(l_node)) ) then
    !                         istat = was_stored
    !                         exit
    !                      end if
    !                   end do
    !                   if ( istat == now_stored ) then
    !                      lst_parts_per_dof_obj (2,touch(l_node)) = lst_parts_per_dof_obj (2,touch(l_node)) + 1
    !                      lst_parts_per_dof_obj (lst_parts_per_dof_obj (2,touch(l_node))+2,touch(l_node)) = aux(2)
    !                   end if
    !                end do
    !             end if
    !          end do

    !          do l_node = 1, femsp%lelem(ielem)%f_inf(l_var)%p%nnode
    !             if ( touch(l_node) /= 0 ) then


    !                lst_parts_per_dof_obj (lst_parts_per_dof_obj(2,touch(l_node))+3:est_max_nparts+2,count_interface) = 0 
    !                ! Zero the rest of entries in current col except last
    !                call sort ( lst_parts_per_dof_obj (2,touch(l_node)), &
    !                     lst_parts_per_dof_obj (3:lst_parts_per_dof_obj(2,touch(l_node))+2,touch(l_node)) )
    !             end if
    !          end do
    !       end if
    !    end do
    ! end do

! subroutine count_interface_dofs_by_face_integration ( iblock, p_trian, femsp, dhand, count_interface, &
!     count_interior, l2ln2o_interior, l2ln2o_interface, est_max_nparts, touch, ws_parts_visited_all, &
!     &   ws_parts_visited_list_all, lst_parts_per_dof_obj, max_nparts, npadj )
!  implicit none
!  ! Parameters
!  integer(ip), intent(in)                     :: iblock
!  type(par_triangulation), intent(in)         :: p_trian 
!  type(fem_space), intent(in)                 :: femsp
!  type(dof_handler), intent(in)               :: dhand
!  integer(ip), intent(inout)                  :: count_interface, count_interior, l2ln2o_interior(:), l2ln2o_interface(:)
!  integer(ip), intent(inout)                  :: est_max_nparts, touch(:,:,:)
!  type(hash_table_ip_ip), intent(inout)       :: ws_parts_visited_all
!  integer(ip), intent(inout)                  :: ws_parts_visited_list_all(:), max_nparts, npadj

!  ! Local variables
!  integer(ip) :: ielem, iprob, ivars, l_var, g_var, inode, i, obje_l, iobje, l_node

!  ! Additional interface DOFs due to ghost dG elements
!  do ielem = p_trian%num_elems+1, p_trian%num_elems+p_trian%num_ghosts
!     !write (*,*) 'ghost element', ielem
!     !write (*,*) 'femsp%lelem(ielem)%elem2dof', femsp%lelem(ielem)%elem2dof
!     iprob = femsp%lelem(ielem)%problem    
!     do ivars = 1, dhand%prob_block(iblock,iprob)%nd1
!        l_var = dhand%prob_block(iblock,iprob)%a(ivars) 
!        g_var = dhand%problems(iprob)%p%l2g_var(l_var)
!        !write (*,*) 'ivars', ivars
!        if ( femsp%lelem(ielem)%continuity(g_var) == 0 ) then ! dG ghost element on the interface
!           do inode = 1, femsp%lelem(ielem)%f_inf(l_var)%p%nnode
!              if ( femsp%lelem(ielem)%elem2dof(inode,l_var) /= 0 ) then 
!                 count_interface = count_interface + 1
!              end if
!           end do
!        end if
!     end do
!  end do

!  write (*,*) ' ESTIMATED BY DG ON GHOSTS ',count_interface

!  ! Additional interface DOFs due to local dG elements
!  do i = 1, p_trian%num_itfc_elems
!     ielem = p_trian%lst_itfc_elems(i)          
!     assert ( ielem <= p_trian%num_elems )
!     iprob = femsp%lelem(ielem)%problem    
!     do ivars = 1, dhand%prob_block(iblock,iprob)%nd1
!        l_var = dhand%prob_block(iblock,iprob)%a(ivars) 
!        g_var = dhand%problems(iprob)%p%l2g_var(l_var)
!        if ( femsp%lelem(ielem)%continuity(g_var) == 0 ) then ! dG local element on the interface
!           ! Identify and put interface DOFs
!           femsp%lelem(ielem)%p_vec%a = 0.0_rp ! Used as touch array
!           do obje_l = p_trian%f_trian%elems(ielem)%topology%nobje_dim(p_trian%f_trian%num_dims), &
!                &      p_trian%f_trian%elems(ielem)%topology%nobje_dim(p_trian%f_trian%num_dims+1)-1
!              iobje = p_trian%f_trian%elems(ielem)%objects(obje_l)
!              assert ( p_trian%f_trian%objects(iobje)%dimension == p_trian%f_trian%num_dims - 1 )
!              if ( p_trian%objects(iobje)%interface /= -1 ) then
!                 do inode = femsp%lelem(ielem)%f_inf(l_var)%p%ntxob%p(obje_l), &
!                      & femsp%lelem(ielem)%f_inf(l_var)%p%ntxob%p(obje_l+1)-1
!                    l_node = femsp%lelem(ielem)%f_inf(l_var)%p%ntxob%l(inode)
!                    if ( femsp%lelem(ielem)%p_vec%a(l_node) == 0.0_rp ) then
!                       femsp%lelem(ielem)%p_vec%a(l_node) = 1.0_rp
!                       count_interface = count_interface + 1
!                    end if
!                 end do
!              end if
!           end do
!           ! Put interior DOFs in the corresponding list
!           do l_node = 1, femsp%lelem(ielem)%f_inf(l_var)%p%nnode
!              if ( femsp%lelem(ielem)%p_vec%a(l_node) == 0.0_rp ) then
!                 count_interior = count_interior + 1
!                 l2ln2o(count_interior) = femsp%lelem(ielem)%elem2dof(l_node,l_var) 
!              end if
!           end do
!        end if
!     end do
!  end do

!  write (*,*) ' ESTIMATED BY DG ON LOCALS ',count_interface

! end subroutine count_interface_dofs_by_face_integration

!*********************************************************************************
! Auxiliary function that returns the position of key in list
!*********************************************************************************
integer(ip) function local_position(key,list,size)
 implicit none
 integer(ip) :: key, size, list(size)

 do local_position = 1,size
    if ( list(local_position) == key) exit
 end do
 assert ( local_position < size + 1 )

end function local_position

end module dof_distribution_create_names
