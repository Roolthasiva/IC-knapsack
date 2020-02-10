module nonradiative
	use constants
	implicit none
	
	type sysdata
		logical										:: do_rad, do_nonrad
		integer										:: ncut, nthresh, nlevels, nsamples, natoms
		character(len=100)							:: bfile, gradfile, algorithm, weighting, radfile, calctype
		real(dbl)									:: k_ic, k_r, e_target, delta_e, gamma, tdm
		real(dbl), dimension(:), allocatable		:: energies, hrfactors, masses, V_vq_j
		real(dbl), dimension(:, :), allocatable		:: fcfactors
		real(dbl), dimension(:, :, :), allocatable	:: Bvqj
		integer, dimension(:, :), allocatable		:: cutoffs, bounds
	contains
		procedure	:: from_file => sysdata_from_file
		procedure	:: fc_compute => sysdata_fc_compute
		procedure	:: cutoff_compute => sysdata_cutoff_compute
		procedure	:: compute_zn => sysdata_compute_zn
		procedure	:: build_V => sysdata_build_V
		procedure	:: calculate_kic => sysdata_calc_kic
		procedure	:: calculate_gamma => sysdata_calc_gamma
		procedure	:: get_next_bound => sysdata_get_next_bound
		procedure	:: screened_ncombinations => sysdata_ncombinations
		procedure	:: free => sysdata_free 
	end type sysdata
	
contains
	
	subroutine sysdata_from_file(sys, filename)
		class(sysdata), intent(inout)	:: sys 
		character(len=*), intent(in)	:: filename
		
	    ! Input related variables
	    character(len=100) :: buffer, label
	    integer 	:: pos
	    integer 	:: ios = 0
	    integer 	:: line = 0
		integer 	:: ix
		real(dbl)	:: tmp_nsamples = 0d0

	    open(main_input_unit, file=filename)

	    ! ios is negative if an end of record condition is encountered or if
	    ! an endfile condition was detected.  It is positive if an error was
	    ! detected.  ios is zero otherwise.

	    do while (ios == 0)
	       read(main_input_unit, '(A)', iostat=ios) buffer
	       if (ios == 0) then
	          line = line + 1

	          ! Find the first instance of whitespace.  Split label and data.
	          pos = scan(buffer, ',')
	          label = trim(buffer(1:pos-1))
	          buffer = buffer(pos+1:)

	          select case (label)
			  case ('spectrum')
		  		 read(buffer, *, iostat=ios) sys%radfile
				 sys%radfile = trim(adjustl(sys%radfile))
			  case ('bfile')
			  	 read(buffer, *, iostat=ios) sys%bfile
				 sys%bfile = trim(adjustl(sys%bfile))
   			  case ('gradfile')
   			  	 read(buffer, *, iostat=ios) sys%gradfile
   				 sys%gradfile = trim(adjustl(sys%gradfile))
      		  case ('algorithm')
      			 read(buffer, *, iostat=ios) sys%algorithm
      			 sys%algorithm = trim(adjustl(sys%algorithm))
         	  case ('weighting')
         		 read(buffer, *, iostat=ios) sys%weighting
         		 sys%weighting = trim(adjustl(sys%weighting))
			  case ('calculation')
			  	 read(buffer, *, iostat=ios) sys%calctype
				 sys%calctype = trim(adjustl(sys%calctype))
	          case ('ncut')
	             read(buffer, *, iostat=ios) sys%ncut
   	          case ('natoms')
   	             read(buffer, *, iostat=ios) sys%natoms
	          case ('nthresh')
	             read(buffer, *, iostat=ios) sys%nthresh
			  case ('nsamples')
			  	 read(buffer, *, iostat=ios) tmp_nsamples
				 sys%nsamples = int(tmp_nsamples)
   			  case ('energy')
   			  	 read(buffer, *, iostat=ios) sys%e_target
   			  case ('deltae')
   			  	 read(buffer, *, iostat=ios) sys%delta_e
			  case ('tdm')
			  	 read(buffer, *, iostat=ios) sys%tdm
			  case ('levels')
			  	 read(buffer, *, iostat=ios) sys%nlevels
				 allocate(sys%energies(sys%nlevels))
				 allocate(sys%hrfactors(sys%nlevels))
				 do ix=1,sys%nlevels
					 read(main_input_unit, '(A)', iostat=ios) buffer
					 pos = scan(buffer, ',')
					 label = buffer(1:pos-1)
					 buffer = buffer(pos+1:)
					 read(label, *, iostat=ios) sys%energies(ix)
					 read(buffer, *, iostat=ios) sys%hrfactors(ix)
				 end do
	          case default
	             print *, 'Skipping invalid label at line', line
	          end select
	       end if
	    end do
		close(main_input_unit)
	end subroutine sysdata_from_file
	
	subroutine sysdata_fc_compute(sys)
		class(sysdata), intent(inout)	:: sys
		
		integer		:: ix, nx
		real(dbl)	:: tmp, yk
		
		if (allocated(sys%fcfactors)) deallocate(sys%fcfactors)
		allocate(sys%fcfactors(sys%nlevels, sys%ncut+1))
		
		do ix=1, sys%nlevels
			yk = sys%hrfactors(ix)
			tmp = exp(-yk)
			do nx=0, sys%ncut
				sys%fcfactors(ix, nx+1) = sqrt(tmp)
				tmp = tmp*yk/real(nx+1)
			end do
		end do
	end subroutine sysdata_fc_compute
	
	subroutine sysdata_cutoff_compute(sys)
		class(sysdata), intent(inout)	:: sys
		
		integer		:: ix, nx, jx, tmpix
		real(dbl)	:: tmp
		logical		:: found
		
		if (allocated(sys%cutoffs)) deallocate(sys%cutoffs)
		allocate(sys%cutoffs(sys%nlevels, sys%nthresh+1))
		sys%cutoffs = 1
		
		do ix=1,sys%nlevels
			tmpix = 1
			tmp = log10(sys%fcfactors(ix, tmpix))
			do nx=0,sys%nthresh
				found = .false.
				do while (.not. found)
					if ((tmp .lt. -nx) .or. (tmpix .eq. sys%ncut)) then
						sys%cutoffs(ix, nx+1) = tmpix
						found = .true.
					else
						tmpix = tmpix+1
						tmp = log10(sys%fcfactors(ix, tmpix))
					end if
				end do
			end do
		end do
		
		if (allocated(sys%bounds)) deallocate(sys%bounds)
		allocate(sys%bounds(sys%nlevels, sys%ncut+1))
		sys%bounds = sys%nthresh+1
		do ix=1,sys%nlevels
			tmpix = 1
			inner: do nx=1,sys%nthresh+1
				do jx=tmpix,sys%ncut+1
					sys%bounds(ix, jx) = nx
				end do
				tmpix = sys%cutoffs(ix, nx)+1
				if (tmpix .eq. sys%ncut+1) exit inner
			end do inner
		end do	
	
	end subroutine sysdata_cutoff_compute
	
	subroutine sysdata_free(sys)
		class(sysdata), intent(inout)	:: sys
		if (allocated(sys%energies)) deallocate(sys%energies)
		if (allocated(sys%hrfactors)) deallocate(sys%hrfactors)
		if (allocated(sys%masses)) deallocate(sys%masses)
		if (allocated(sys%fcfactors)) deallocate(sys%fcfactors)
		if (allocated(sys%V_vq_j)) deallocate(sys%V_vq_j)
		if (allocated(sys%Bvqj)) deallocate(sys%Bvqj)
		if (allocated(sys%cutoffs)) deallocate(sys%cutoffs)
		if (allocated(sys%bounds)) deallocate(sys%bounds)
	end subroutine sysdata_free
	
	real(dbl) function	compute_kfcn(sys, occs) result(kfcn)
		class(sysdata), intent(in) 					:: sys
		integer, dimension(sys%nlevels), intent(in)	:: occs
		
		integer :: ix
		kfcn = 1d0
		do ix = 1, sys%nlevels
			kfcn = kfcn * sys%fcfactors(ix, occs(ix)+1)
		end do
	end function compute_kfcn
	
	subroutine sysdata_compute_zn(sys, occs, res)
		class(sysdata), intent(inout)					:: sys
		integer, dimension(sys%nlevels), intent(in)		:: occs
		real(dbl), dimension(sys%nlevels), intent(out)	:: res
		
		integer		:: jx
		real(dbl)	:: kfcn, tmp
		
		kfcn = compute_kfcn(sys, occs)
		do jx=1, sys%nlevels
			res(jx) = 0.5d0 * sys%energies(jx) / sys%hrfactors(jx)
			tmp = real(occs(jx)) - sys%hrfactors(jx)
			res(jx) = sqrt(res(jx) * tmp * tmp)
			res(jx) = res(jx) * kfcn
		end do
	end subroutine sysdata_compute_zn
	
	subroutine sysdata_build_V(sys, grads)
		class(sysdata), intent(inout)	:: sys
		
		integer								:: b_ios, g_ios, vx, qx, dummy1, dummy2
		character(len=1)					:: dummy_char1, dummy_char2
		real(dbl), dimension(sys%nlevels)	:: tmp
		real(dbl), dimension(sys%natoms, 3) :: grads
		
		if (allocated(sys%masses)) deallocate(sys%masses)
		allocate(sys%masses(sys%natoms))
		if (allocated(sys%V_vq_j)) deallocate(sys%V_vq_j)
		allocate(sys%V_vq_j(sys%nlevels))
		if (allocated(sys%Bvqj)) deallocate(sys%Bvqj)
		allocate(sys%Bvqj(sys%natoms, 3, sys%nlevels))
		
		open(gradfile_unit, file=sys%gradfile)
		readgrads: do vx=1,sys%natoms
			do qx=1,3
				read(gradfile_unit, *, iostat=g_ios) sys%masses(vx), grads(vx, qx)
				if (g_ios .ne. 0) then
					print *, 'Error reading grads, ierr=', g_ios
					exit readgrads
				end if
			end do
		end do readgrads
		close(gradfile_unit)
		
		open(bfile_unit, file=sys%bfile)
		read(bfile_unit, *, iostat=b_ios)
		sys%V_vq_j = 0d0
		readbfile: do vx=1,sys%natoms
			do qx=1,3
				read(bfile_unit, *, iostat=b_ios) dummy_char1, dummy_char2, dummy1, dummy2, tmp(:)
				sys%Bvqj(vx, qx, :) = tmp(:)
				if (b_ios .ne. 0) then
					print *, 'Error reading B-values, ierr=', b_ios
					exit readbfile
				else
					sys%V_vq_j(:) = sys%V_vq_j(:) + grads(vx, qx) * tmp(:) / sys%masses(vx)
				end if
			end do
		end do readbfile
		close(bfile_unit)
		
		sys%V_vq_j = sys%V_vq_j * V_CONVERT / TO_S
	end subroutine sysdata_build_V
	
	subroutine sysdata_calc_gamma(sys)
		class(sysdata), intent(inout)	:: sys
		
		integer		:: ix
		real(dbl)	:: be, w, tmp
		sys%gamma = 0d0
		do ix=1, sys%nlevels
			w  = sys%energies(ix)
			be = exp(w / (KB*300d0)) - 1d0
			be = 1d0/be
			w  = w / PLANCK
			tmp = w * w * sys%hrfactors(ix) * (2d0 * be + 1)
			sys%gamma = sys%gamma + tmp
		end do
	
		sys%gamma = SQRT_8LN2 * sqrt(sys%gamma)
	end subroutine sysdata_calc_gamma
	
	subroutine sysdata_calc_kic(sys, noccs, occs, init)
		class(sysdata), intent(inout)						:: sys
		integer(bigint), intent(in)							:: noccs
		integer, dimension(sys%nlevels, noccs), intent(in)	:: occs
		logical, intent(in)									:: init
		
		integer		:: nx
		real(dbl)	:: res(sys%nlevels), tmp
		real(dbl)	:: grads(sys%natoms, 3)
		
		if (init) then
			sys%k_ic = 0d0
			if (.not. allocated(sys%V_vq_j)) call sys%build_V(grads)
			call sys%calculate_gamma
		end if
		
		do nx=1,noccs
			call sys%compute_zn(occs(:, nx), res)
			tmp = dot_product(res, sys%V_vq_j)
			sys%k_ic = sys%k_ic + tmp*tmp
		end do
		
		sys%k_ic = 4d0 * sys%k_ic / sys%gamma 
	end subroutine sysdata_calc_kic
	
	subroutine sysdata_get_next_bound(sys, occ, ix, bnd)
		class(sysdata), intent(in)					:: sys
		integer, dimension(sys%nlevels), intent(in)	:: occ
		integer, intent(in)							:: ix
		integer, intent(out)						:: bnd
		
		integer	:: jx
		bnd = sys%nthresh + 2
		do jx=1,ix
			bnd = bnd - sys%bounds(jx, occ(jx)+1)
		end do
		bnd = max(1, bnd)

	end subroutine sysdata_get_next_bound
		
	subroutine sysdata_ncombinations(sys, maxnocc)
		class(sysdata), intent(in)		:: sys
		integer(bigint), intent(out)	:: maxnocc
		
		integer :: ix, occ(sys%nlevels)
		maxnocc = 0
		occ = 0
		occ(1) = sys%cutoffs(1, sys%nthresh+1)
		call next_n(sys, occ, 1, maxnocc)
	end subroutine
	
	recursive subroutine next_n(sys, occ, ix, maxnocc)
		type(sysdata), intent(in)						:: sys
		integer(bigint), intent(out) 					:: maxnocc 
		integer, intent(in)								:: ix
		integer, dimension(sys%nlevels), intent(inout)	:: occ
		
		integer :: maxix, jx, bnd
		integer(bigint) :: tmpmax
		maxix = occ(ix)
		maxnocc = 1
		if (ix .eq. sys%nlevels) then
			maxnocc = maxix + 1
		else
			do jx=0,maxix
				occ(ix) = jx
				call sys%get_next_bound(occ, ix, bnd)
				occ(ix+1) = sys%cutoffs(ix+1, bnd)
				call next_n(sys, occ, ix+1, tmpmax)
				maxnocc = maxnocc + tmpmax
			end do
		end if
	end subroutine next_n	
end module