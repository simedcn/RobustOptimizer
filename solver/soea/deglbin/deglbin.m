function [xmin, fmin, out] = deglbin(fitfun, lb, ub, maxfunevals, options)
% DEGLBIN DEGL Algorithm
% DEGLBIN(fitfun, lb, ub, maxfunevals) minimize the function fitfun in
% box constraints [lb, ub] with the maximal function evaluations
% maxfunevals.
% DEGLBIN(..., options) minimize the function by solver options.
if nargin <= 4
	options = [];
end

defaultOptions.NP = 100;
defaultOptions.CR = 0.5;
defaultOptions.NeighborhoodRatio = 0.1;
defaultOptions.Display = 'off';
defaultOptions.RecordPoint = 100;
defaultOptions.ftarget = -Inf;
defaultOptions.TolStagnationIteration = Inf;
defaultOptions.initial.X = [];
defaultOptions.initial.f = [];
defaultOptions.initial.w = [];
defaultOptions.initial.psai = [];
defaultOptions.ConstraintHandling = 'Interpolation';
defaultOptions.EpsilonValue = 0;
defaultOptions.nonlcon = [];
defaultOptions.EarlyStop = 'none';

options = setdefoptions(options, defaultOptions);
CR = options.CR;
isDisplayIter = strcmp(options.Display, 'iter');
RecordPoint = max(0, floor(options.RecordPoint));
ftarget = options.ftarget;
TolStagnationIteration = options.TolStagnationIteration;

if isequal(options.ConstraintHandling, 'Interpolation')
	interpolation = true;
else
	interpolation = false;
end

nonlcon = options.nonlcon;
EpsilonValue = options.EpsilonValue;
if ~isempty(strfind(options.ConstraintHandling, 'EpsilonMethod'))
	EpsilonMethod = true;
else
	EpsilonMethod = false;
end

if ~isempty(strfind(options.EarlyStop, 'auto'))
	EarlyStop = true;
else
	EarlyStop = false;
end

D = numel(lb);

if ~isempty(options.initial)
	options.initial = setdefoptions(options.initial, defaultOptions.initial);
	X = options.initial.X;
	fx = options.initial.f;
	w = options.initial.w;
	psai_x = options.initial.psai;
else
	X = [];
	fx = [];
	w = [];
	psai_x = [];
end

if isempty(X)
	NP = options.NP;
else
	[~, NP] = size(X);
end

% Initialize variables
counteval = 0;
countiter = 1;
countStagnation = 0;
countcon = 0;
out = initoutput(RecordPoint, D, NP, maxfunevals, ...
	'countcon', ...
	'FC');

% Initialize contour data
if isDisplayIter
	[XX, YY, ZZ] = advcontourdata(D, lb, ub, fitfun);
end

% Initialize population
if isempty(X)
	X = zeros(D, NP);
	for i = 1 : NP
		X(:, i) = lb + (ub - lb) .* rand(D, 1);
	end
end

% w
if isempty(w)
	w = 0.05 + 0.9 * rand(1, NP);
end

% Evaluation
if isempty(fx)
	fx = zeros(1, NP);
	for i = 1 : NP
		fx(i) = feval(fitfun, X(:, i));
		counteval = counteval + 1;
	end
end

% Constraint violation
if isempty(psai_x) && EpsilonMethod
	psai_x = zeros(1, NP);
	for i = 1 : NP		
		clbx = lb - X(:, i);
		cubx = X(:, i) - ub;
		psai_x(i) = sum(clbx(clbx > 0)) + sum(cubx(cubx > 0));
		
		if ~isempty(nonlcon)			
			[cx, ceqx] = feval(nonlcon, X(:, i));
			countcon = countcon + 1;
			psai_x(i) = psai_x(i) + sum(cx(cx > 0)) + sum(ceqx(ceqx > 0));
		end
	end
end

% Sort
if ~EpsilonMethod
	[fx, fidx] = sort(fx);
	X = X(:, fidx);
    w = w(fidx);
else
	PsaiFx = [psai_x', fx'];
	[~, SortingIndex] = sortrows(PsaiFx);
	X = X(:, SortingIndex);
	fx = fx(SortingIndex);
    w = w(SortingIndex);
	psai_x = psai_x(SortingIndex);
end

% Initialize variables
k = ceil(0.5 * (options.NeighborhoodRatio * NP));
wc = w;
V = X;
U = X;
fu = zeros(1, NP);
FC = zeros(1, NP);		% Consecutive Failure Counter
rt = zeros(1, NP);
r1 = zeros(1, NP);
r2 = zeros(1, NP);
psai_u = zeros(1, NP);

% Display
if isDisplayIter
	displayitermessages(...
		X, U, fx, countiter, XX, YY, ZZ);
end

% Record
out = updateoutput(out, X, fx, counteval, countiter, ...
	'countcon', countcon, ...
	'FC', FC);

% Iteration counter
countiter = countiter + 1;

while true
	% Termination conditions
	outofmaxfunevals = counteval > maxfunevals - NP;
	if ~EarlyStop
		if outofmaxfunevals
			break;
		end
	else		
		reachftarget = min(fx) <= ftarget;
		TolX = 10 * eps(mean(X(:)));
		solutionconvergence = std(X(:)) <= TolX;
		TolFun = 10 * eps(mean(fx));
		functionvalueconvergence = std(fx(:)) <= TolFun;
		stagnation = countStagnation >= TolStagnationIteration;
		
		if outofmaxfunevals || ...
				reachftarget || ...
				solutionconvergence || ...
				functionvalueconvergence || ...
				stagnation
			break;
		end
	end
	
	for i = 1 : NP
		rt(i) = i;
		
		% Generate r1
		r1(i) = floor(1 + NP * rand);
		while rt(i) == r1(i)
			r1(i) = floor(1 + NP * rand);
		end
		
		% Generate r2
		r2(i) = floor(1 + NP * rand);
		while rt(i) == r2(i) || r1(i) == r2(i)
			r2(i) = floor(1 + NP * rand);
		end
	end
	
	% Mutation
	% Global best
	g_best = 1;
	
	for i = 1 : NP
		% Generate random mutant factor F, and parameters, alpha and beta.
		F = abs(0.5 * log(rand));
		alpha = F;
		beta = F;
		
		% Neiborhoods index
		n_index = (rt(i)-k) : (rt(i)+k);
		lessthanone = n_index < 1;
		n_index(lessthanone) = n_index(lessthanone) + NP;
		greaterthanNP = n_index > NP;
		n_index(greaterthanNP) = n_index(greaterthanNP) - NP;
		
		% Neiborhood solutions and fitness
		Xn = X(:, n_index);
		fn = fx(n_index);
		
		% Best neiborhood
		[~, n_besti] = min(fn);
		Xn_besti = Xn(:, n_besti);
		
		% Random neiborhood index
		n_index(n_index == rt(i)) = [];
		Xn = X(:, n_index);
		p = ceil(rand * numel(n_index));
		q = ceil(rand * numel(n_index));
		
		while p == q
			q = ceil(rand * numel(n_index));
		end
		
		% Random neiborhood solutions
		Xp = Xn(:, p);
		Xq = Xn(:, q);
		
		% Local donor vector
		Li = X(:, rt(i)) + alpha * (Xn_besti - X(:, rt(i))) + ...
			beta * (Xp - Xq);
		
		% Global donor vector
		gi = X(:, rt(i)) + alpha * (X(:, g_best) - X(:, rt(i))) + ...
			beta * (X(:, r1(i)) - X(:, r2(i)));
		
		% Self-adaptive weight factor
		wc(i) = w(rt(i)) + F * (w(g_best) - w(rt(i))) + ...
			F * (w(r1(i)) - w(r2(i)));
		
		if wc(i) < 0.05
			wc(i) = 0.05;
		elseif wc(i) > 0.95
			wc(i) = 0.95;
		end
		
		V(:, i) = wc(i) * gi + (1 - wc(i)) * Li;
	end
	
	for i = 1 : NP
		% Binominal Crossover
		jrand = floor(1 + D * rand);
		for j = 1 : D
			if rand < CR || j == jrand
				U(j, i) = V(j, i);
			else
				U(j, i) = X(j, rt(i));
			end
		end
	end
	
	if interpolation
		% Correction for outside of boundaries
		for i = 1 : NP
			for j = 1 : D
				if U(j, i) < lb(j)
					U(j, i) = 0.5 * (lb(j) + X(j, rt(i)));
				elseif U(j, i) > ub(j)
					U(j, i) = 0.5 * (ub(j) + X(j, rt(i)));
				end
			end
		end
	end
	
	% Display
	if isDisplayIter
		displayitermessages(...
			X, U, fx, countiter, XX, YY, ZZ);
	end
	
	% Evaluation
	for i = 1 : NP
		fu(i) = feval(fitfun, U(:, i));
		counteval = counteval + 1;
	end
	
	% Constraint violation
	if EpsilonMethod
		for i = 1 : NP
			clbu = lb - U(:, i);
			cubu = U(:, i) - ub;
			psai_u(i) = sum(clbu(clbu > 0)) + sum(cubu(cubu > 0));
			
			if ~isempty(nonlcon)
				[cu, cequ] = feval(nonlcon, U(:, i));
				countcon = countcon + 1;
				psai_u(i) = psai_u(i) + sum(cu(cu > 0)) + sum(cequ(cequ > 0));
			end
		end
	end
	
    if ~EpsilonMethod
        % Selection
        FailedIteration = true;
        for i = 1 : NP
            if fu(i) < fx(i)
                X(:, i)		= U(:, i);
                fx(i)		= fu(i);
                w(i)		= wc(i);
                FailedIteration = false;
                FC(i)		= 0;
            else
                FC(i) = FC(i) + 1;
            end
        end
    else
		% Epsilon level comparisons
		FailedIteration = true;
		for i = 1 : NP
			X_AND_U_IN_EPSILON = psai_u(i) < EpsilonValue && psai_x(i) < EpsilonValue;
			X_AND_U_EQUAL_EPSILON = psai_u(i) == psai_x(i);
			
			if ((X_AND_U_IN_EPSILON || X_AND_U_EQUAL_EPSILON) && fu(i) < fx(i)) || ...
					(~X_AND_U_IN_EPSILON && psai_u(i) < psai_x(i))
				X(:, i)		= U(:, i);
				fx(i)		= fu(i);
                w(i)		= wc(i);
				FailedIteration = false;
				FC(i)		= 0;
				psai_x(i)	= psai_u(i);
			else
				FC(i) = FC(i) + 1;				
			end
		end
    end
	
	% Sort
	if ~EpsilonMethod
		[fx, fidx] = sort(fx);
		X = X(:, fidx);
        w = w(fidx);
		FC = FC(fidx);
	else
		PsaiFx = [psai_x', fx'];
		[~, SortingIndex] = sortrows(PsaiFx);
		X = X(:, SortingIndex);
		fx = fx(SortingIndex);
        w = w(SortingIndex);
		FC = FC(SortingIndex);
		psai_x = psai_x(SortingIndex);
	end	
	
	% Record
	out = updateoutput(out, X, fx, counteval, countiter, ...
		'countcon', countcon, ...
		'FC', FC);
	
	% Iteration counter
	countiter = countiter + 1;
	
	% Stagnation iteration
	if FailedIteration
		countStagnation = countStagnation + 1;
	else
		countStagnation = 0;
	end
end

fmin = fx(1);
xmin = X(:, 1);

final.w = w;
final.psai = psai_x;

out = finishoutput(out, X, fx, counteval, countiter, ...
	'countcon', countcon, ...
	'final', final, ...
	'FC', zeros(NP, 1));
end
