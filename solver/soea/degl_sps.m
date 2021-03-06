function [xmin, fmin, out] = degl_sps(fitfun, lb, ub, maxfunevals, options)
% DEGL_SPS DEGL Algorithm with SPS Framework
% DEGL_SPS(fitfun, lb, ub, maxfunevals) minimize the function fitfun in
% box constraints [lb, ub] with the maximal function evaluations
% maxfunevals.
% DEGL_SPS(..., options) minimize the function by solver options.
if nargin <= 4
	options = [];
end

defaultOptions.NP = 100;
defaultOptions.CR = 0.5;
defaultOptions.Q = 70;
defaultOptions.NeighborhoodRatio = 0.1;
defaultOptions.Display = 'off';
defaultOptions.RecordPoint = 100;
defaultOptions.ftarget = -Inf;
defaultOptions.TolStagnationIteration = Inf;
defaultOptions.initial.X = [];
defaultOptions.initial.f = [];
defaultOptions.initial.w = [];
defaultOptions.ConstraintHandling = 'Interpolation';

options = setdefoptions(options, defaultOptions);
CR = options.CR;
Q = options.Q;
isDisplayIter = strcmp(options.Display, 'iter');
RecordPoint = max(0, floor(options.RecordPoint));
ftarget = options.ftarget;
TolStagnationIteration = options.TolStagnationIteration;

if isequal(options.ConstraintHandling, 'Interpolation')
	interpolation = true;
else
	interpolation = false;
end

D = numel(lb);

if ~isempty(options.initial)
	options.initial = setdefoptions(options.initial, defaultOptions.initial);
	X = options.initial.X;
	fx = options.initial.f;
	w = options.initial.w;
else
	X = [];
	fx = [];
	w = [];
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
out = initoutput(RecordPoint, D, NP, maxfunevals, ...
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

% Sort
[fx, fidx] = sort(fx);
X = X(:, fidx);
w = w(fidx);

% Initialize variables
k = ceil(0.5 * (options.NeighborhoodRatio * NP));
wc = w;
V = X;
U = X;
fu = zeros(1, NP);
FC = zeros(1, NP);		% Consecutive Failure Counter
SP = X;
fSP = fx;
iSP = 1;

% Display
if isDisplayIter
	displayitermessages(...
		X, U, fx, countiter, XX, YY, ZZ);
end

% Record
out = updateoutput(out, X, fx, counteval, countiter, ...
	'FC', FC);

% Iteration counter
countiter = countiter + 1;

while true
	% Termination conditions
	outofmaxfunevals = counteval > maxfunevals - NP;
	reachftarget = min(fx) <= ftarget;
	stagnation = countStagnation >= TolStagnationIteration;	
	if outofmaxfunevals || reachftarget || stagnation
		break;
	end
	
	% Mutation
	% Global best
	[~, ibestX] = min(fx);
	[~, ibestSP] = min(fSP);
	
	for i = 1 : NP
		% Generate random mutant factor F, and parameters, alpha and beta.
		F = abs(0.5 * log(rand));
		alpha = F;
		beta = F;
		
		% Neiborhoods index
		n_index = (i-k) : (i+k);
		lessthanone = n_index < 1;
		n_index(lessthanone) = n_index(lessthanone) + NP;
		greaterthanNP = n_index > NP;
		n_index(greaterthanNP) = n_index(greaterthanNP) - NP;
		
		% Neiborhood solutions and fitness
		if FC(i) <= Q
			Xn = X(:, n_index);
			fn = fx(n_index);
		else
			Xn = SP(:, n_index);
			fn = fSP(n_index);			
		end
		
		% Best neiborhood
		[~, n_besti] = min(fn);
		Xn_besti = Xn(:, n_besti);
		
		% Random neiborhood index
		n_index(n_index == i) = [];
		
		if FC(i) <= Q
			Xn = X(:, n_index);
		else
			Xn = SP(:, n_index);			
		end
		
		p = ceil(rand * numel(n_index));
		q = ceil(rand * numel(n_index));
		
		while p == q
			q = ceil(rand * numel(n_index));
		end
		
		% Random neiborhood solutions
		Xp = Xn(:, p);
		Xq = Xn(:, q);
		
		% Generate r1
		r1 = floor(1 + NP * rand);
		while i == r1
			r1 = floor(1 + NP * rand);
		end
		
		% Generate r2
		r2 = floor(1 + NP * rand);
		while i == r2 || r1 == r2
			r2 = floor(1 + NP * rand);
		end
		
		% Local donor vector
		if FC(i) <= Q
			Li = X(:, i) + alpha * (Xn_besti - X(:, i)) + ...
				beta * (Xp - Xq);
			
			% Global donor vector
			gi = X(:, i) + alpha * (X(:, ibestX) - X(:, i)) + ...
				beta * (X(:, r1) - X(:, r2));			
			
			% Self-adaptive weight factor
			wc(i) = w(i) + F * (w(ibestX) - w(i)) + ...
				F * (w(r1) - w(r2));
		else
			Li = SP(:, i) + alpha * (Xn_besti - SP(:, i)) + ...
				beta * (Xp - Xq);
			
			% Global donor vector
			gi = SP(:, i) + alpha * (SP(:, ibestSP) - SP(:, i)) + ...
				beta * (SP(:, r1) - SP(:, r2));
			
			% Self-adaptive weight factor
			wc(i) = w(i) + F * (w(ibestSP) - w(i)) + ...
				F * (w(r1) - w(r2));
		end
		
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
		if FC(i) <= Q
			for j = 1 : D
				if rand < CR || j == jrand
					U(j, i) = V(j, i);
				else
					U(j, i) = X(j, i);
				end
			end
		else
			for j = 1 : D
				if rand < CR || j == jrand
					U(j, i) = V(j, i);
				else
					U(j, i) = SP(j, i);
				end
			end			
		end
	end
	
	if interpolation
		% Correction for outside of boundaries
		for i = 1 : NP
			if FC(i) <= Q
				for j = 1 : D
					if U(j, i) < lb(j)
						U(j, i) = 0.5 * (lb(j) + X(j, i));
					elseif U(j, i) > ub(j)
						U(j, i) = 0.5 * (ub(j) + X(j, i));
					end
				end
			else
				for j = 1 : D
					if U(j, i) < lb(j)
						U(j, i) = 0.5 * (lb(j) + SP(j, i));
					elseif U(j, i) > ub(j)
						U(j, i) = 0.5 * (ub(j) + SP(j, i));
					end
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
	
	% Selection
	FailedIteration = true;
	for i = 1 : NP		
		if fu(i) < fx(i)
			X(:, i)		= U(:, i);
			fx(i)		= fu(i);
			w(i)		= wc(i);
			SP(:, iSP)	= U(:, i);
			fSP(iSP)	= fu(i);
			iSP			= mod(iSP, NP) + 1;
			FailedIteration = false;
			FC(i)		= 0;
		else
			FC(i) = FC(i) + 1;
		end
	end
	
	% Sort		
	[fx, fidx] = sort(fx);
	X = X(:, fidx);
	w = w(fidx);
	FC = FC(fidx);
	
	% Record
	out = updateoutput(out, X, fx, counteval, countiter, ...
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

[fmin, minindex] = min(fx);
xmin = X(:, minindex);

out = finishoutput(out, X, fx, counteval, countiter, ...
	'FC', zeros(NP, 1));
end