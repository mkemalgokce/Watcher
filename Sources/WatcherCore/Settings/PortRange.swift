public enum PortRange {
    public static func isValid(_ port: Int) -> Bool {
        (1 ... 65535).contains(port)
    }
}
