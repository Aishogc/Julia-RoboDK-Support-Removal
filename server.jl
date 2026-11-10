using HTTP, JSON3, NearestNeighbors, Base64

const ROOT = @__DIR__

function triangles(bytes::Vector{UInt8})
    length(bytes) >= 15 || error("STL file too small")
    if length(bytes) >= 84
        n = Int(ltoh(reinterpret(UInt32, bytes[81:84])[1]))
        if n > 0 && 84 + 50n == length(bytes)
            io = IOBuffer(bytes); seek(io, 84)
            out = Matrix{Float64}(undef, 3, 3n)
            for i in 1:n
                read(io, 12)
                for j in 1:3, k in 1:3
                    out[k, 3(i-1)+j] = Float64(read(io, Float32))
                end
                read(io, 2)
            end
            all(isfinite, out) || error("Non-finite STL coordinates")
            return out
        end
    end
    txt = try String(bytes) catch; error("Not a valid binary or ASCII STL") end
    matches = collect(eachmatch(r"(?m)^\s*vertex\s+([\d.eE+\-]+)\s+([\d.eE+\-]+)\s+([\d.eE+\-]+)\s*$", txt))
    !isempty(matches) && length(matches) % 3 == 0 || error("Unrecognized STL structure")
    out = Matrix{Float64}(undef, 3, length(matches))
    for (i,m) in enumerate(matches), k in 1:3
        out[k,i] = parse(Float64, m.captures[k])
    end
    all(isfinite, out) || error("Non-finite STL coordinates")
    out
end

function detect(a, b, tolerance)
    # Approximate vertex proximity classification, retaining the user's existing any-sample logic.
    tree = KDTree(a)
    candidate = falses(size(b,2) ÷ 3)
    for f in eachindex(candidate)
        p = @view b[:,3*f-2:3*f]
        center = vec(sum(p,dims=2)) ./ 3
        candidate[f] = any(sqrt(knn(tree, k == 4 ? center : p[:,k], 1, true)[2][1]) > tolerance for k in 1:4)
    end
    candidate
end

# Approximate attachment locations: candidate support vertices within a contact radius
# of original-mesh vertices, grouped spatially. These are NOT machining-ready targets.
function contacts(a, b, mask, tolerance)
    tree = KDTree(a)
    radius = max(1.0, 2.0*tolerance)
    pts = NTuple{3,Float64}[]
    for f in eachindex(mask)
        mask[f] || continue
        for j in 1:3
            p = @view b[:,3*(f-1)+j]
            d = sqrt(knn(tree, p, 1, true)[2][1])
            if d <= radius
                push!(pts, (p[1],p[2],p[3]))
            end
        end
    end
    isempty(pts) && return NamedTuple[]
    # Cluster using occupied spatial cells and 26-neighbor connectivity.
    cellsize = max(1.0, 2.0*tolerance)
    bins = Dict{NTuple{3,Int},Vector{Int}}()
    for (i,p) in enumerate(pts)
        key = (floor(Int,p[1]/cellsize),floor(Int,p[2]/cellsize),floor(Int,p[3]/cellsize))
        push!(get!(bins,key,Int[]),i)
    end
    visited = Set{NTuple{3,Int}}()
    clusters = NamedTuple[]
    for key in keys(bins)
        key in visited && continue
        queue = [key]; push!(visited,key)
        sx=sy=sz=0.0; n=0
        while !isempty(queue)
            c = pop!(queue)
            for i in bins[c]
                p=pts[i]; sx+=p[1];sy+=p[2];sz+=p[3];n+=1
            end
            for dx in -1:1,dy in -1:1,dz in -1:1
                nb=(c[1]+dx,c[2]+dy,c[3]+dz)
                if haskey(bins,nb) && !(nb in visited)
                    push!(visited,nb);push!(queue,nb)
                end
            end
        end
        n >= 3 && push!(clusters,(x=sx/n,y=sy/n,z=sz/n,samples=n))
    end
    sort!(clusters,by=c->-c.samples)
    [(id=i,x=c.x,y=c.y,z=c.z,samples=c.samples) for (i,c) in enumerate(clusters)]
end

respond_json(obj;status=200) = HTTP.Response(status,["Content-Type"=>"application/json","Cache-Control"=>"no-store"],JSON3.write(obj))

function handler(req)
    path = split(String(req.target),'?')[1]
    if req.method == "GET" && (path == "/" || path == "/index.html")
        return HTTP.Response(200,["Content-Type"=>"text/html; charset=utf-8"],read(joinpath(ROOT,"web","index.html")))
    elseif req.method == "GET" && path == "/health"
        return respond_json((ok=true,))
    elseif req.method == "POST" && path == "/detect"
        try
            data = JSON3.read(String(req.body))
            a = triangles(Vector{UInt8}(base64decode(String(data.original))))
            b = triangles(Vector{UInt8}(base64decode(String(data.supported))))
            tolerance = Float64(data.tolerance)
            (0.01 <= tolerance <= 10.0) || error("Tolerance must be 0.01–10 mm")
            size(a,2) <= 600_000 && size(b,2) <= 600_000 || error("Mesh exceeds 200,000 triangles")
            mask = detect(a,b,tolerance)
            points = contacts(a,b,mask,tolerance)
            return respond_json((mask=collect(mask),total=length(mask),flagged=count(mask),contacts=points,
                note="Approximate vertex-based classification and contact estimates; meshes must be aligned. Verify before machining or printing."))
        catch e
            @error "Detection failed" exception=(e,catch_backtrace())
            return respond_json((error=sprint(showerror,e),);status=400)
        end
    end
    HTTP.Response(404,"Not found")
end

port = parse(Int,get(ENV,"PORT","8080"))
println("STL Viewer listening on 0.0.0.0:$port")
HTTP.serve(handler,"0.0.0.0",port;max_body_bytes=120_000_000)
