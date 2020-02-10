module knapsack
	use constants, only : dbl, bigint, print_frequency
	use progress, only : progress_bar_time
	use nonradiative
	implicit none
contains
	subroutine knap_01(capacity, n, values, res)
		integer, intent(in)					:: n
		real(dbl), intent(in) 				:: capacity
		real(dbl), dimension(n), intent(in)	:: values
		integer, dimension(n), intent(out)  :: res
		
		integer									:: maxcap, w, ix, jx, err
		real(dbl)								:: wt
		logical									:: was_added
		real(dbl), allocatable, dimension(:, :)	:: table
		
		maxcap = ceiling(capacity)+1
		allocate(table(maxcap, n+1), stat=err)
		res = 0
		table = 0d0
		
		do jx=2,n+1
			wt = values(jx-1)
			do ix=2,maxcap
				if (wt > ix-1) then
					table(ix, jx) = table(ix, jx-1)
				else
					table(ix, jx) = max(table(ix, jx-1), table(ix-int(wt), jx-1) + wt)
				end if
			end do
		end do
		
		w = maxcap
		do jx=n+1,2,-1
			was_added = (table(w, jx) .ne. table(w, jx-1))
			if (was_added) then
				res(jx-1) = 1
				wt = values(jx-1)
				w = w - int(wt)
			end if
			if (w .le. 0d0) then
				exit
			end if
		end do
		
		deallocate(table)
	end subroutine knap_01
	
	subroutine fptas(capacity, n, values, epsilon, res, sumres)
		real(dbl), intent(in)				:: capacity, epsilon
		integer, intent(in)					:: n
		real(dbl), dimension(n), intent(in) :: values
		integer, dimension(n), intent(out)  :: res
		real(dbl), intent(out)				:: sumres
		
		real(dbl)				:: K
		real(dbl), dimension(n)	:: new_values
		integer					:: ix
		
		K = epsilon * maxval(values) / real(n)
		new_values = values / K
		
		call knap_01(capacity/K, n, new_values, res)
		sumres = dot_product(values, res)
	end subroutine fptas
	
	subroutine expand(n, energies, occs, res)
		integer, intent(in)								  :: n
		real(dbl), dimension(n), intent(in) 			  :: energies
		integer, dimension(n), intent(in)  				  :: occs
		real(dbl), allocatable, dimension(:), intent(out) :: res
		
		integer	:: ix, jx, ctr, ntot
		ntot = sum(occs)
		allocate(res(ntot))
		
		ctr = 1
		do ix=1,n
			do jx=1,occs(ix)
				res(ctr) = energies(ix)
				ctr = ctr + 1
			end do
		end do
	end subroutine expand
	
	subroutine contract(nbase, ntot, base, total, res)
		integer, intent(in) 			  	   :: nbase, ntot
		integer, dimension(nbase), intent(in)  :: base
		integer, dimension(ntot), intent(in)   :: total
		integer, dimension(nbase), intent(out) :: res
		
		integer	:: ctr, ix, jx
		ctr = 1
		do ix=1,nbase
			res(ix) = sum(total(ctr:ctr+base(ix)-1))
			ctr = ctr + base(ix)
		end do
	end subroutine contract
	
	subroutine knap_n(capacity, n, energies, occs, epsilon, res, sumres)
		integer, intent(in)					:: n
		real(dbl), intent(in) 				:: capacity, epsilon
		real(dbl), dimension(n), intent(in)	:: energies
		integer, dimension(n), intent(in)	:: occs
		integer, dimension(n), intent(out)  :: res
		real(dbl), intent(out)				:: sumres
		
		integer								 :: ntot
		integer, allocatable, dimension(:) 	 :: tempres
		real(dbl), allocatable, dimension(:) :: totvalues
		
		call expand(n, energies, occs, totvalues)
		ntot = size(totvalues)
		allocate(tempres(ntot))
		call fptas(capacity, ntot, totvalues, epsilon, tempres, sumres)
		call contract(n, ntot, occs, tempres, res)
		deallocate(tempres)
		deallocate(totvalues)
	end subroutine knap_n
	
	recursive subroutine iterate(n, noccs, values, max_occs, min_occs, emax, emin, occ, ix, occlist, enlist, occix, checked, maxnocc)
		integer, intent(in)								:: n, ix
		integer(bigint), intent(in)						:: noccs, maxnocc
		integer(bigint), intent(inout)					:: occix, checked
		integer, dimension(n), intent(in) 				:: max_occs, min_occs
		integer, dimension(n), intent(inout)			:: occ
		real(dbl), dimension(n), intent(in) 			:: values
		integer, dimension(n, noccs), intent(inout) 	:: occlist
		real(dbl), dimension(noccs), intent(inout)		:: enlist
		real(dbl), intent(in)							:: emax, emin
		
		integer		:: i
		real(dbl) 	:: en
		do i=min_occs(ix),max_occs(ix)
			occ(ix) = i
			
			if (ix .lt. n) then
				call iterate(n, noccs, values, max_occs, min_occs, emax, emin, occ, ix+1, occlist, enlist, occix, checked, maxnocc)
			else
				en = dot_product(values, occ)
				if ((en .lt. emax) .and. (en .gt. emin)) then
					occlist(1:n, occix) = occ(1:n)
					enlist(occix) = en
					occix = occix+1
				end if
				checked = checked + 1
				if (mod(checked, print_frequency) .eq. 1) call progress_bar_time(checked, maxnocc)
			end if
		end do		
	end subroutine iterate
	
	integer(bigint) function ncombinations(n, max_occs, min_occs) result(max_nocc)
		integer, intent(in)					:: n
		integer, dimension(n), intent(in)	:: max_occs, min_occs
		integer								:: ix
		
		max_nocc = 1
		do ix=1,n
			max_nocc = max_nocc * (max_occs(ix) - min_occs(ix) + 1)
		end do
	end function ncombinations
	
	subroutine brute_force(n, values, max_occs, min_occs, emax, emin, occlist, enlist, noccs)
		integer, intent(in)									:: n
		integer, dimension(n), intent(in) 					:: max_occs, min_occs
		real(dbl), dimension(n), intent(in) 				:: values
		real(dbl), intent(in)								:: emax, emin
		integer, allocatable, dimension(:, :), intent(out)	:: occlist
		real(dbl), allocatable, dimension(:), intent(out)	:: enlist
		integer(bigint), intent(out)						:: noccs
		
		integer(bigint) :: max_nocc, occsize, checked
		integer	:: cocc(n), ix
		cocc = 0
		cocc(1) = max(min_occs(1), 1)
		max_nocc = ncombinations(n, max_occs, min_occs)
		occsize = max_nocc / 10
		
		allocate(occlist(n, occsize))
		allocate(enlist(occsize))
		noccs = 1
		checked = 0
		write(*, '(1x,a,1x,e12.4,1x,a)') 'Estimated', real(max_nocc), 'occupations to check'
		call iterate(n, occsize, values, max_occs, min_occs, emax, emin, cocc, 1, occlist, enlist, noccs, checked, max_nocc)
		call progress_bar_time(max_nocc, max_nocc)
		write(*, *)
	end subroutine brute_force
	
	subroutine screened_brute_force(sys, emax, emin, occlist, enlist, noccs, worst_case)
		type(sysdata), intent(in)							:: sys
		real(dbl), intent(in)								:: emax, emin
		integer, allocatable, dimension(:, :), intent(out)	:: occlist
		real(dbl), allocatable, dimension(:), intent(out)	:: enlist
		integer(bigint), intent(in)							:: worst_case
		integer(bigint), intent(out)						:: noccs
		
		integer(bigint)	:: max_nocc, occsize, checked
		integer	:: cocc(sys%nlevels), ix
		cocc = 0
		cocc(1) = sys%cutoffs(1, sys%nthresh+1)
		call sys%screened_ncombinations(max_nocc)
		occsize = max_nocc / 2
		
		allocate(occlist(sys%nlevels, occsize))
		allocate(enlist(occsize))
		noccs = 1
		checked = 0
		write(*, '(1x,a,1x,e12.4,1x,a,e12.4)') 'Estimated', real(max_nocc), 'occupations to check of a possible', real(worst_case)
		call screened_iterate(sys, occsize, emax, emin, cocc, 1, occlist, enlist, noccs, checked, max_nocc)
		call progress_bar_time(max_nocc, max_nocc)
		write(*, *)
	end subroutine screened_brute_force
	
	recursive subroutine screened_iterate(sys, noccs, emax, emin, occ, ix, occlist, enlist, occix, checked, maxnocc)
		type(sysdata), intent(in)								:: sys
		integer, intent(in)										:: ix
		integer(bigint), intent(in)								:: noccs, maxnocc
		integer(bigint), intent(inout)							:: occix, checked
		integer, dimension(sys%nlevels), intent(inout)			:: occ
		integer, dimension(sys%nlevels, noccs), intent(inout) 	:: occlist
		real(dbl), dimension(noccs), intent(inout)				:: enlist
		real(dbl), intent(in)									:: emax, emin
		
		integer		:: i, maxix, bnd
		real(dbl) 	:: en
		maxix = occ(ix)
		if (ix .eq. sys%nlevels) then
			do i=0,maxix
				occ(ix) = i
				en = dot_product(sys%energies, occ)
				if ((en .lt. emax) .and. (en .gt. emin)) then
					occlist(:, occix) = occ(:)
					enlist(occix) = en
					occix = occix+1
				end if
				checked = checked + 1
				if (mod(checked, print_frequency) .eq. 1) call progress_bar_time(checked, maxnocc)
			end do
		else
			do i=0,maxix
				occ(ix) = i
				call sys%get_next_bound(occ, ix, bnd)
				occ(ix+1) = sys%cutoffs(ix+1, bnd)
				call screened_iterate(sys, noccs, emax, emin, occ, ix+1, occlist, enlist, occix, checked, maxnocc)
			end do
		end if
	end subroutine screened_iterate
	
end module knapsack		
		