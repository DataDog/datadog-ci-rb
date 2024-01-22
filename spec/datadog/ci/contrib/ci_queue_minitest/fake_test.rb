require "minitest"

class SomeTest < Minitest::Test
  def test_pass
    assert true
  end

  def test_pass_other
    assert true
  end

  def test_fail
    assert false
  end
end
